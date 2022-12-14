# Create ksqlDB tombstone event based on another field

Based on another field, we want to create a tombstone event so that a person 
entry is deleted in a KTable.

## Set up environment

Run docker-compose file:
```
docker-compose up -d
```

Start ksqlDB CLI:
````
docker exec -it ksqldb-cli ksql http://ksqldb-server:8088
````

## Queries

### Initial Stream
We start with an initial stream containing information about a person.

```roomsql
CREATE STREAM PERSON(
    ID STRING KEY,
    AGE INT,
    NAME STRING,
    ACTION STRING
    )
    WITH(
    KAFKA_TOPIC='person',
    PARTITIONS=1,
    VALUE_FORMAT='JSON');
```

### Tombstone logic
Based on the value (create, update, delete) of the `Action` column,
we want to create the tombstone event.
We follow this [blog article](https://rmoff.net/2020/11/03/kafka-connect-ksqldb-and-kafka-tombstone-messages/).
It is important to set `VALUE_FORMAT` to Kafka and cast null as varchar.

```roomsql
CREATE STREAM PERSON_PROCESSED
WITH(KAFKA_TOPIC='person-processed',VALUE_FORMAT='KAFKA')
AS SELECT
    ID,
    CASE
        WHEN ACTION ='delete'
        THEN CAST(NULL AS VARCHAR)
        ELSE CONCAT('{"AGE": "', CAST(AGE AS STRING), '", "NAME": "', NAME,  '", "ACTION": "', ACTION, '"}') END AS VALUE
FROM PERSON
EMIT CHANGES;
```
In the next stream, we reconvert the `VALUE_FORMAT` back to JSON as well as recreate the original structure.
```roomsql
CREATE STREAM PERSON_PROCESSED_JSON
WITH(KAFKA_TOPIC='person-processed-json',VALUE_FORMAT='JSON')
AS SELECT
    ID,
    CAST(EXTRACTJSONFIELD(VALUE, '$.AGE') AS INT) AS AGE,
    EXTRACTJSONFIELD(VALUE, '$.NAME') AS NAME,
    EXTRACTJSONFIELD(VALUE, '$.ACTION') AS ACTION
FROM PERSON_PROCESSED
EMIT CHANGES;
```

And we create the final KTable.
```roomsql
CREATE TABLE PERSON_TABLE(
    ID VARCHAR PRIMARY KEY,
    AGE INT,
    NAME VARCHAR,
    ACTION VARCHAR
    )
    WITH (
    KAFKA_TOPIC = 'person-processed-json',
    VALUE_FORMAT='JSON');
```

## Test
We select the final KTable and in a second tab
we insert some events into the initial stream.
```roomsql
INSERT INTO PERSON (ID, AGE, NAME, ACTION) VALUES ('1', 10, 'Alex', 'update');
INSERT INTO PERSON (ID, AGE, NAME, ACTION) VALUES ('2', 20, 'Jon', 'update');
INSERT INTO PERSON (ID, AGE, NAME, ACTION) VALUES ('3', 30, 'Sven', 'update');
```

Finally, we insert the delete event
```roomsql
INSERT INTO PERSON (ID, AGE, NAME, ACTION) VALUES ('2', 20, 'Jon', 'delete');
```

The table should look like this:

```shell
ksql> select * from PERSON_TABLE emit changes;
+------------------+--------------------------+---------------------------+--------------------------------+
|ID                |AGE                       |NAME                       |ACTION                          |
+------------------+--------------------------+---------------------------+--------------------------------+
|1                 |10                        |Alex                       |update                          |
|2                 |20                        |Jon                        |update                          |
|3                 |30                        |Sven                       |update                          |
|2                 |<TOMBSTONE>               |<TOMBSTONE>                |<TOMBSTONE>                     |
```

and the corresponding topic:
```shell
ksql> print 'person-processed-json';
Key format: JSON or KAFKA_STRING
Value format: JSON or KAFKA_STRING
rowtime: 2022/11/29 18:03:36.262 Z, key: 1, value: {"AGE":10,"NAME":"Alex","ACTION":"update"}, partition: 0
rowtime: 2022/11/29 18:03:36.318 Z, key: 2, value: {"AGE":20,"NAME":"Jon","ACTION":"update"}, partition: 0
rowtime: 2022/11/29 18:03:36.361 Z, key: 3, value: {"AGE":30,"NAME":"Sven","ACTION":"update"}, partition: 0
rowtime: 2022/11/29 18:03:44.074 Z, key: 2, value: <null>, partition: 0
```
