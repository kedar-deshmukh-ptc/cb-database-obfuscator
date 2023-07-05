/*Audit trail logs*/
BEGIN
  DECLARE
    obfuscate_audit_trial BOOLEAN DEFAULT FALSE;
    v_name                VARCHAR2(50);
    v_id                  NUMBER(10);
    CURSOR c_users IS SELECT id, name FROM users;
  BEGIN
    IF obfuscate_audit_trial
    THEN
      OPEN c_users;
      LOOP
        FETCH c_users INTO v_id, v_name;
        EXIT WHEN c_users%NOTFOUND;

        -- "bond's personal wiki"
        UPDATE audit_trail_logs
        SET details = REPLACE(details, '"' || v_name || '''s Personal Wiki"', '"user-' || v_id || '''s Personal Wiki"');

        -- "bond [1]"
        UPDATE audit_trail_logs
        SET details = REPLACE(details, '"' || v_name || ' [' || v_id || ']"', '"user-' || v_id || ' [' || v_id || ']"');

        -- {"name":"bond","id":1}
        UPDATE audit_trail_logs
        SET details = REPLACE(details, '{"name":"' || v_name || '","id":' || v_id || '}',
                              '{"name":"user-' || v_id || '", "id":' || v_id || '}');

        -- {"id":1,"name":"bond"}
        UPDATE audit_trail_logs
        SET details = REPLACE(details, '{"id":' || v_id || ',"name":"' || v_name || '"}',
                              '{"id":' || v_id || ',"name":"user-' || v_id || '"}');
        COMMIT;
      END LOOP;
      CLOSE c_users;
    END IF;
  END;
END;
/

CREATE OR REPLACE FUNCTION SHOULD_OBFUSCATE(
  field_value CLOB, label_id NUMBER)
  RETURN NUMBER IS
  BEGIN
    /*date 2019-08-20 22:00:00*/
    IF (NOT regexp_like(field_value,
                        '^([1-2][0-9]{3})-([0-1][0-9])-([0-3][0-9])( [0-2][0-9]):([0-5][0-9]):([0-5][0-9])$', 'cn'))
       /*Anything containing a whitespace and not a date should be obfuscated*/
       AND ((regexp_like(field_value, '\s+', 'cn')) OR
            /*color #5eceeb*/
            ((NOT regexp_like(field_value, '^#([a-fA-F0-9]{6})$', 'cn')) AND
             /*Number 14*/
             (NOT regexp_like(field_value, '^[0-9]+$', 'cn')) AND
             /*boolean*/
             (NOT regexp_like(field_value, '^(true|false)$', 'cn')) AND
             /*one or more reference 9-1041#3152/1*/
             (NOT regexp_like(field_value, '^(([0-9]{1,2}-[0-9]{4,}#[0-9]{4,}(\/)[0-9]{1,},)?)+([0-9]{1,2}-[0-9]{4,}#[0-9]{4,}(\/)[0-9]{1,})$', 'cn')) AND
             /*one or more test case reference in test run 9-1793116/1#13306428/1*/
             (NOT regexp_like(field_value, '^(([0-9]{1,2}-[0-9]{4,}(\/)[0-9]{1,}#[0-9]{4,}(\/)[0-9]{1,},)?)+([0-9]{1,2}-[0-9]{4,}(\/)[0-9]{1,}#[0-9]{4,}(\/)[0-9]{1,})$', 'cn')) AND
             /*one or more issue or item [ITEM:1010#3331/1];[ITEM:1011#3332/1]*/
             (NOT regexp_like(field_value, '^((\[(ITEM|ISSUE):[0-9]{4,}#[0-9]{4,}\/[0-9]{1,}\];)?)+(\[(ITEM|ISSUE):[0-9]{4,}#[0-9]{4,}\/[0-9]{1,}\])$', 'cn')) AND
             /*Test run ID  label_id:1000104 value:2750e123c70a910cd6278a2c69f53676*/
             ((label_id < 1000000) OR
              MOD(label_id, 10) != 4 OR
              (NOT regexp_like(field_value, '^([0-9]|[a-f]){32}$', 'cn'))
             ))) THEN
      return 1;
    ELSE
      return 0;
    END IF;
  END;
/

/*obfuscate acl role*/
UPDATE acl_role
SET name        = id,
    description = NULL
WHERE name <> 'codeBeamer Review Project Review Role'
  AND name <> 'Project Admin'
  AND name <> 'Developer'
  AND name <> 'Stakeholder';
COMMIT;

/*object_reference*/
UPDATE object_reference
SET url = 'file://' || from_id
WHERE url LIKE 'file://%';
UPDATE object_reference
SET url = 'mailto:' || from_id || '@testemail.testemail'
WHERE url LIKE 'mailto:%';
UPDATE object_reference
SET url = '/' || from_id
WHERE url LIKE '/%';

/*obfuscate urls in wiki fields*/
UPDATE object_reference
SET url = 'url-something'
WHERE to_id IS NULL
AND to_type_id IS NULL
AND assoc_id IS NULL
AND field_id IS NOT NULL;

/*obfuscate usernames in url*/
update (select obj_ref.url, u.name, u.id from object_reference obj_ref inner join users u on LOWER(obj_ref.url) like u.name) 
set url=replace(url, name, concat('user-', id));

COMMIT;

/*remove all file content except: vintage reports, calendar, work calendars*/
TRUNCATE TABLE object_revision_blobs;
COMMIT;

/*update name of artifacts except: calendars, work calendars, roles, groups, member group,
  state transition, field definitions, choice option, release rank, review config,
  review tracker, state transition, transition condition, workflow action, artifact file link*/
UPDATE object_revision r
SET r.name = r.object_id || '-artifact ' || substr(r.name, 1, 4) || ' :' || LENGTH(r.name)
WHERE r.name NOT IN ('codeBeamer Review Project Review Tracker',
                     'codeBeamer Review Project Review Item Tracker',
                     'codeBeamer Review Project Review Config Template Tracker')
  AND r.type_id NOT IN (9, 10, 17, 18, 19, 21, 23, 25, 26, 33, 35, 44);
COMMIT;

/*update description of artifacts, except: calendar, work calendar, association
  state transition, transition condition, workflow action*/
UPDATE object_revision r
SET r.description = REGEXP_REPLACE(r.description, '"description":\s*"((\\"|[^"])*)"',
                                   '"description":"Obfuscated description-' ||
                                   LENGTH(r.description) || '"')
WHERE r.TYPE_ID NOT IN (9, 10, 17, 23, 24, 28);
COMMIT;

/*update key, category of projects and trackers*/
UPDATE object_revision r
    SET r.description = REGEXP_REPLACE(
                      REGEXP_REPLACE(r.description, '"keyName":"[^"]*"', '"keyName":"K-' || r.proj_id || '"'),
                      '"category":"[^"]*"', '"category":"TestCategory"')
    WHERE r.type_id IN (22, 16);
COMMIT;

/*Update categoryName of project categories*/
UPDATE object_revision r
SET r.description = REGEXP_REPLACE(r.description, '"categoryName":"[^"]*"', '"categoryName":"' || r.name || '"')
WHERE r.type_id=42;
COMMIT;

/*delete simple comment message*/
UPDATE object_revision r
SET r.description = 'Obfuscated description-' || LENGTH(r.description)
WHERE r.type_id IN (13, 15)
  AND r.description IS NOT JSON;

/*delete description of : file, folder, baseline, user, tracker, dashboard*/
UPDATE object_revision r
SET r.description = NULL
WHERE r.type_id IN (1, 2, 12, 30, 31, 32, 34);
COMMIT;

/*update user data*/
UPDATE users
SET name               = 'user-' || id,
    passwd             = NULL,
    hostname           = NULL,
    firstname          = 'First-' || id,
    lastname           = 'Last-' || id,
    title              = NULL,
    address            = NULL,
    zip                = NULL,
    city               = NULL,
    state              = NULL,
    country            = NULL,
    language           = NULL,
    geo_country        = NULL,
    geo_region         = NULL,
    geo_city           = NULL,
    geo_latitude       = NULL,
    geo_longitude      = NULL,
    source_of_interest = NULL,
    scc                = NULL,
    team_size          = NULL,
    division_size      = NULL,
    company            = NULL,
    email              = 'user' || id || '@testemail.testemail',
    email_client       = NULL,
    phone              = NULL,
    mobil              = NULL,
    skills             = NULL,
    unused0            = NULL,
    unused1            = NULL,
    unused2            = NULL,
    referrer_url       = NULL
WHERE name NOT IN ('system', 'computed.update', 'deployment.executor', 'scm.executor');
COMMIT;

/*remove user photos*/
TRUNCATE TABLE users_small_photo_blobs;
COMMIT;
TRUNCATE TABLE users_large_photo_blobs;
COMMIT;

/*remove user preferences: DOORS_BRIDGE_LOGIN(63),JIRA_SERVER_LOGIN(67),SLACK_USER_ID(2001),SLACK_USER_TOKEN(2002)*/
DELETE
FROM user_pref
WHERE pref_id IN (63, 67, 2001, 2002);
COMMIT;

/*remove user keys*/
TRUNCATE TABLE user_key;
COMMIT;

/*rename projects*/
UPDATE existing
SET name     = 'Project' || proj_id,
    key_name = 'K-' || proj_id
WHERE name <> 'codeBeamer Review Project';
COMMIT;

/*remove jira synch*/
TRUNCATE TABLE object_job_schedule;
COMMIT;

/*update task summary and description*/
UPDATE task
SET summary = 'Task' || id || ' ' || substr(summary, 1, 4) || ' :' || LENGTH(summary)
WHERE summary IS NOT NULL;
COMMIT;

UPDATE task
SET details = TO_CHAR(LENGTH(details))
WHERE details IS NOT NULL;
COMMIT;

/*UPDATE custom field value (not choice data)*/
UPDATE task_field_value
SET field_value = (
    CASE
      WHEN TRIM(TRANSLATE(substr(field_value, 1, 100), '0123456789-,.', ' ')) IS NULL
              THEN '1'
      ELSE TO_CHAR(substr(field_value, 1, 2) || ' :' || LENGTH(field_value))
        END)
WHERE field_value IS NOT NULL
    AND (label_id IN (3, 80) OR (label_id >= 1000 AND SHOULD_OBFUSCATE(field_value, label_id) = 1));
COMMIT;

/*UPDATE summary, description and custom field value*/
UPDATE task_field_history
SET old_value = (
    CASE
      WHEN old_value IS NOT NULL AND SHOULD_OBFUSCATE(old_value, label_id) = 1 THEN (
        CASE
          WHEN TRIM(TRANSLATE(substr(old_value, 1, 100), '0123456789-,.', ' ')) IS NULL
                  THEN TO_CHAR(revision - 1)
          ELSE TO_CHAR(substr(old_value, 1, 2) || ' :' || LENGTH(old_value))
            END)
      ELSE NULL END
    ),
    new_value = (
        CASE
          WHEN new_value IS NOT NULL AND SHOULD_OBFUSCATE(old_value, label_id) = 1 THEN (
            CASE
              WHEN TRIM(TRANSLATE(substr(new_value, 1, 100), '0123456789-,.', ' ')) IS NULL
                      THEN TO_CHAR(revision)
              ELSE TO_CHAR(substr(new_value, 1, 2) || ' :' || LENGTH(new_value))
                END)
          ELSE NULL END
        )
WHERE label_id IN (3, 80) OR label_id >= 10000;
COMMIT;

/*TASK_TYPE reduce prefix to 2 characters*/
UPDATE task_type
SET prefix = substr(prefix, 1, 2);
COMMIT;

/*remove report jobs*/
TRUNCATE TABLE object_quartz_schedule;
COMMIT;

/*UPDATE tag name*/
UPDATE label
SET name = 'LABEL' || id
WHERE name NOT IN ('FINISHED_TESTRUN_GENERATION');
COMMIT;

UPDATE workingset
SET name        = 'WS-' || id,
    description = NULL
WHERE name != 'member';
COMMIT;

DELETE FROM background_job;
COMMIT;

DELETE FROM background_step;
COMMIT;

TRUNCATE TABLE document_cache_data_blobs;
COMMIT;

TRUNCATE TABLE document_cache_data;
COMMIT;

TRUNCATE TABLE background_job_meta;
COMMIT;

TRUNCATE TABLE background_step_result;
COMMIT;

TRUNCATE TABLE background_step_context;
COMMIT;

/*remove stored configs*/
TRUNCATE TABLE application_configuration;
COMMIT;

DROP FUNCTION SHOULD_OBFUSCATE;