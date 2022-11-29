-- Create initial Stream
set 'auto.offset.reset' = 'earliest';
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

-- Tombstone Logic
CREATE STREAM PERSON_PROCESSED
WITH(KAFKA_TOPIC='person-processed',VALUE_FORMAT='KAFKA')
AS SELECT
    ID,
    CASE
        WHEN ACTION ='delete'
        THEN CAST(NULL AS VARCHAR)
        ELSE CONCAT('{AGE: ', CAST(AGE AS STRING), ', NAME: ', NAME, ', ACTION: ', ACTION, '}') END AS VALUE
FROM PERSON
EMIT CHANGES;

-- Convert back to JSON
CREATE STREAM PERSON_PROCESSED_JSON
WITH(KAFKA_TOPIC='person-processed-json',VALUE_FORMAT='JSON')
AS SELECT
    ID,
    VALUE
FROM PERSON_PROCESSED
EMIT CHANGES;


-- Create table
CREATE TABLE PERSON_TABLE(
    ID VARCHAR PRIMARY KEY,
    VALUE VARCHAR
    )
    WITH (
    KAFKA_TOPIC = 'person-processed-json',
    VALUE_FORMAT='JSON');

-- Insert events
INSERT INTO PERSON (ID, AGE, NAME, ACTION) VALUES ('1', 10, 'Alex', 'update');
INSERT INTO PERSON (ID, AGE, NAME, ACTION) VALUES ('2', 20, 'Jon', 'update');
INSERT INTO PERSON (ID, AGE, NAME, ACTION) VALUES ('3', 30, 'Sven', 'update');

-- Insert delete
INSERT INTO PERSON (ID, AGE, NAME, ACTION) VALUES ('2', 20, 'Jon', 'delete');