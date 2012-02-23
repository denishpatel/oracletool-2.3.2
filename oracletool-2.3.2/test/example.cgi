#!/opt/lampp/bin/perl

# This CGI example simply connects to an Oracle 
# database, selects sysdate from dual, and
# displays it on a web page. If this script does
# not run successfully, then Oracletool probably 
# wil not run either.

# Example of using the Perl DBI and DBD::Oracle
# modules to access an Oracle database.
# Also shows use of the CGI module to create
# a web page.

# Grab the required modules

   use DBI;
   use CGI;
   use CGI::Carp;

# ALWAYS use strict.
# strict forces you to use proper variable declaration.

   use strict;

# Declare variables

   my ($database,$username,$password,$connect_string,$dbh,$sql,$cursor,$time);

# Set variables

   $database = "ora10g";
   $username = "username";
   $password = "password";

# This is how you set an environmental variable as 
# in a perl script.

   $ENV{'ORACLE_HOME'}	= '/Applications/instantclient10_1';
   $ENV{'TNS_ADMIN'}	= '/Applications/instantclient10_1/sqlnet';

# Make connection to the database..
# $connect_string is a DBD::Oracle specific connect string.

   $connect_string = "dbi:Oracle:$database";

# $dbh is a database handle (an open connection, if successful).
# Complain if the connection is not successful.

   $dbh = DBI->connect($connect_string,$username,$password) or
      carp "Unable to connect to Oracle ($DBI::errstr)\n";

# Set the SQL you want to run

   $sql = "select to_char(SYSDATE,'Day, Month DD HH24:MI:SS') from dual";

# Prepare it (This is where the SQL will be parsed be the Oracle engine).
# If your statement is going to fail, this is where it will happen.

   $cursor = $dbh->prepare($sql) or
      carp "Unable to connect to Oracle ($DBI::errstr)\n";

# Execute the statement.

   $cursor->execute;

# Fetch the results.

   $time = $cursor->fetchrow_array;

# Finish the query.

   $cursor->finish;

# Disconnect from the database.

   $dbh->disconnect;

# Start creating the HTML page.

# First, print the content-type, followed by a blank line
   print << "EOF";
Content-type: Text/html\n\n
<HTML>
  <HEAD>
    <TITLE>Current time</TITLE>
  </HEAD>
  <BODY BGCOLOR="#b0b0b0">
    <CENTER>
    <P>
    <B>
Current time for database $database.
    </B>
    <P>
    <TABLE BORDER>
      <TH>Time</TH>
      <TR>
        <TD>$time</TD>
      </TR>
    </TABLE>
    </CENTER>
  </BODY>
</HTML>
EOF
