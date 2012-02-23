--  Oracletool is written more from a DBA standpoint than
-- developer. In the past, the tool checked for the explicit
-- "SELECT ANY TABLE" privilege upon a user logging in. This
-- is no longer true. But, because Oracletool depends on so
-- many 'DBA%', 'V$%' views, and system level tables, a user
-- needs some degree of authority, albeit select only, on these
-- data dictionary objects.  In order to make the tool available
-- to both DBA and developer, you may want to run this included
-- 'create_role.sql' script, which will prompt you for a role
-- name, which will be created, and may be granted to users who
-- are allowed to access data dictionary views, but not rows from
-- all tables in the database (SELECT ANY TABLE). The exception is
-- that it will not grant privileges to any '%LINK%' views or tables,
-- thus preventing said user from obtaining passwords for existing
-- database links.
--
-- The Oracletool distribution is Copyright (c) 
-- 1998 - 2009 Adam vonNieda - Kansas USA

SET HEADING OFF;
SET FEEDBACK OFF;
SET ECHO OFF;
spool foo;
PROMPT
PROMPT Note: This script shuld be run via SQL*Plus as SYS.
PROMPT 
PROMPT Please choose a name for the role to be created for Oracletool users.
PROMPT This name must not conflict with existing user or role names.
PROMPT Example: ORACLETOOL
PROMPT
ACCEPT ROLENAME PROMPT 'Enter the role name: '
PROMPT
PROMPT Creating role &ROLENAME
SPOOL dobedobedo.sql;
SELECT 'Create role &ROLENAME;' FROM DUAL;
SELECT 'Grant create session to &ROLENAME;' FROM DUAL;
SELECT 'Grant select on '||OWNER||'.'||OBJECT_NAME||' to &ROLENAME;' FROM DBA_OBJECTS
WHERE (
   OBJECT_NAME LIKE 'DBA_%'
   OR OBJECT_NAME LIKE 'V$%'
   OR OBJECT_NAME LIKE 'GV$%'
   OR OBJECT_NAME LIKE 'V_$%'
   OR OBJECT_NAME LIKE 'GV_$%'
   OR OBJECT_NAME LIKE '%$'
      )
AND OBJECT_NAME NOT LIKE '%LINK%'
AND OWNER = 'SYS'
AND OBJECT_TYPE != 'SYNONYM';
SPOOL OFF;
PROMPT
PROMPT Creating role &ROLENAME
PROMPT

SET ECHO ON;

@@dobedobedo

SET ECHO OFF;

PROMPT
PROMPT &ROLENAME role creation should now be complete.
PROMPT You may grant this role to users who may access
PROMPT Oracletool from a developer standpoint.
PROMPT
EXIT;
