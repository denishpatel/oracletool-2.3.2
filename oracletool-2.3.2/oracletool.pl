#!/usr/bin/perl

#   Copyright (c) 1998 - 2010 Adam vonNieda - Kansas USA
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file,
#   with the exception that it cannot be placed on a CD-ROM or similar media
#   for commercial distribution without the prior approval of the author.

#   This software is provided without warranty of any kind. If your server
#   melts as a result of using this script, that's a bummer. But it won't.

require 5.003;

use strict;
use CGI qw(:standard);
use File::Basename;
use FileHandle;

if (! eval "require DBI") {
   ErrorPage("It appears that the DBI module is not installed!");
}

use DBD::Oracle qw(:ora_session_modes);

use vars qw($VERSION $scriptname $query $database $namesdatabase $schema $textarea_w);
use vars qw($debug $object_type $object_name $statement_id $user $whereclause $textarea_h);
use vars qw($expire $username $password $dbh $sql $majversion $minversion $rowdisplay $banner);
use vars qw($oracle7 $oracle8 $oracle8i $oracle9i $oracle92 $db_block_size $title $heading $cursor);
use vars qw($logging $explainschema $bgcolor $headingcolor $fontcolor $infocolor $font $fontsize);
use vars qw($linkcolor $cellcolor $bordercolor $description %themes $schema_cols $menufontsize);
use vars qw($expiration $oraclenames $theme $repository $logfile %plugins $config_file);
use vars qw($encryption_string $bgimage $menuimage $encryption_enabled $copyright $headingfont);
use vars qw($headingfontcolor $encryption_method $dbstatus $myoracletool $mydbh $notoracle7 $oraclei); 
use vars qw($explainpassword $myoracletoolexpire $norefreshbutton $hostname $statspack_schema);
use vars qw($upload_limit $nls_date_format $oracle10 $oracle11);

$VERSION = "2.3.2";

# Edit the following if you want to use a config file not named "oracletool.ini".
# The following assumes that the file is in the same directory as oracletool.pl.

$config_file		= "oracletool.ini";

$nls_date_format	= "Mon DD YYYY @ HH24:MI:SS";

Main();

#=============================================================
# Nothing but subroutines from here on.
#=============================================================

sub Main {

   my ($foo);

# Unbuffer STDOUT
   $|++;

# Find out the name this script was invoked as.
   $scriptname = $ENV{'SCRIPT_NAME'};

# Get the data from the elements passed in the URL.
   $query		= new CGI;
   $database		= $query->param('database');
   $namesdatabase	= $query->param('namesdatabase');
   $schema		= $query->param('schema');
   $explainschema	= $query->param('explainschema');
   $explainpassword	= $query->param('explainpassword');
   $object_type		= $query->param('object_type');
   $object_name         = $query->param('arg');
   $statement_id	= $query->param('statement_id');
   $user		= $query->param('user');
   $whereclause		= $query->param('whereclause');
   $expire		= $query->param('expire');
   $myoracletoolexpire	= $query->param('myoracletoolexpire');
   $password		= $query->param('password');

# Set the page colors / font etc.
# Attempt to get a cookie containing the users theme.
# Set to a default theme if none is found.
# Attempt to get a cookie containing MyOracletool info.

   $theme = cookie("OracletoolTheme");
   $theme = "Default" unless ($theme);
   $myoracletool = cookie("MyOracletool");

# Get the settings from the config file.
   parseConfig();

# Decide whether to display copyright in all SQL statements.
   if ($ENV{'DISPLAY_COPYRIGHT'}) {
      $copyright = "/* Oracletool v$VERSION is copyright 1998 - 2010 Adam vonNieda, Kansas USA */ ";
   } else {
      $copyright = "";
   }

   logit("Enter subroutine Main");

   logit("Database = $database Object type = $object_type ARG = $object_name");

# Check for cookie encryption functionality.

   encryptionEnabled();

# Set the properties that will override the default theme.
   doProperties();

# If $namesdatabase is not null, then they have entered
# a names-resolved database. Change the $database value
# to the $namesdatabase value.
   $database = $namesdatabase if $namesdatabase;

# If $database is "About_oracletool" then
# show the "About" page.
   if ( $database && $database  eq "About_oracletool" ) {
      about();
   }

# The $user variable will get passed to get session info
# for an individual user. If no individual user is passed
# then it defaults to % (All users)
   $user 		= "%" unless $user;

# Get rid of the +'s on multi-word object types.
   $object_type =~ s/\+/ / if $object_type;

# If invoked standalone, show main page with database list.
   if ( ! defined $database ) {
      createMainPage();
      exit;
   }

# Skip the password verification for setting theme. Theme
# will be sent to browser as cookie.
   if ($object_type eq "SETTHEME") {
      setTheme();
   }

# Skip the password verification for setting My Oracletool
# parameters (cookies).
   if ($object_type eq "MYORACLETOOLCREATE" && $query->param('command') eq "savecookie") {
      logit("Redirecting to myOracletoolCreate");
      myOracletoolCreate();
   }

# Skip the password verification for setting Properties. Properties
# will be sent to browser as cookie.
   if ($object_type eq "SETPROPS") {
      setProperties();
   }

# Skip the password verification for explain plan. Password
# will be entered on the explain plan screen.
   if ($object_type eq "EXPLAIN") {
      enterExplainPlan();
   }

# Add a password if no cookie is found, or if incorrect. 
   if ($object_type eq "ADDPASSWORD")     {
      $username = $query->param('username');
      $password = $query->param('password');
      addPasswd($database,$username,$password);
   }

# Attempt to get username and password cookies for connecting to the specified database. 
   ($username,$password) = split / /, GetPasswd($database);

# If no cookie is found, do not try to connect to the database,
# just go directly to the password screen.
   unless ($username && $password) {
      EnterPasswd($database);
   }

# Make connection to the database
   $dbh = dbConnect($database,$username,$password);

# Find out what version of Oracle we are dealing with.

   getDbVersion($dbh);

# If invoked the first time after selecting the database,
# start creating the frames.

   if ( $object_type eq "FRAMEPAGE" ) {
      framePage();
   }

# Run an explain plan after determining the database version.
# This is required to determine which PLAN_TABLE sql should
# be executed, should a PLAN_TABLE not exist for the schema
# name passed, and said schema may not have privileges to see
# what version the database is.
   if ($object_type eq "RUNEXPLAINPLAN") {
      runExplainPlan();
   }

# See what status the database is in (OPEN,MOUNTED etc...). 

   $dbstatus = dbStatus();

# Display the menu on the left side of the screen.
# This connects to the database as well, hence the
# $username variable. Connection is for determining 
# version, OPS etc. Certain buttons will or will not
# be display based on some queries.

   if ( $object_type eq "MENU" ) {
# If the database is MOUNTED (not open), show 
# a partial menu
      if ($dbstatus eq "MOUNTED") {
         shortMenu($username);
      } else {
         showMenu($username);
      }
   }

   if ($dbstatus eq "OPEN") {

# Find out the database block size

      $db_block_size = getDBblocksize();

# Get the Server banner to display the version info.

      $banner = getBanner();

   }

# Create the header for the HTML page.

   $title      = "$database: Oracletool v$VERSION connected as $username";
   $heading    = "";

   Header($title,$heading,$font,$fontsize,$fontcolor,$bgcolor);

# The Director subroutine will direct the script to the appropriate
# subroutines based on the parameters passed, namely $object_type

   Director();

# Disconnect from the database

   $dbh->disconnect;

# Finish the HTML page.

   Footer();

   logit("Exit subroutine Main");
}

sub getDbVersion {

   logit("Enter subroutine getDbVersion");

   my $dbh = shift;
   my ($value);

   $oracle7	= "";
   $oracle8	= "";
   $oracle8i	= "";
   $oracle9i	= "";
   $oracle92	= "";
   $oracle10	= "";
   $notoracle7	= "";
   $oraclei	= "";
   $oracle11	= "";

# Find out if we are dealing with Oracle7 or Oracle8
   logit("   Getting Oracle version");
#   $sql = "$copyright
#SELECT MAX(SUBSTR(RELEASE,1,1)),
#       MAX(SUBSTR(RELEASE,3,1))
#   FROM V\$COMPATIBILITY
#";

   $sql = "$copyright
SELECT 
   VALUE
FROM V\$PARAMETER 
   WHERE NAME = 'compatible'
";

   $cursor = $dbh->prepare($sql);
   if (defined $cursor) {
      $cursor->execute;
      $value = $cursor->fetchrow_array;
      logit("   Version is $value");
      ($majversion,$minversion) = split(/\./,$value);
      $cursor->finish;
      logit("   Major version = $majversion, Minor = $minversion");
      if ( $majversion eq "7" ) {
         logit("   This is an Oracle7 database.");
         logit("   Why are you still on version 7?.");
         $oracle7 = "Yep";
      }
      if ( $majversion eq "8" ) {
         $oracle8 = "Yep";
         $notoracle7 = "Yep";
         logit("   This is an Oracle8 database.");
         if ($minversion eq "1") {
            logit("   This is an Oracle8i database.");
            $oracle8i = "Yep";
            $oraclei = "Yep";
         }
      }
      if ( $majversion eq "9" ) {
         $oracle9i = "Yep";
         $oraclei = "Yep";
         $notoracle7 = "Yep";
         logit("   This is an Oracle9i database.");
         if ($minversion eq "2") {
            logit("   This is 9i release 2 (9.2).");
            $oracle92 = "Yep";
         }
      }
      if ( $majversion eq "10" ) {
         $oracle10 = "Yep";
         $oraclei = "Yep";
         $notoracle7 = "Yep";
         logit("   This is an Oracle10g database.");
      }
      if ( $majversion eq "11" ) {
         $oracle11 = "Yep";
         $oraclei = "Yep";
         $notoracle7 = "Yep";
         logit("   This is an Oracle11g database.");
      }
   } else {
      logit("Object type is $object_type");
      if ($object_type eq "FRAMEPAGE") {
         ErrorPage("<HR>The user you connected as does not have sufficient database privileges to run " .
         "Oracletool. Please log in as a different user, preferably one with SELECT ANY TABLE and SELECT ANY DICTIONARY privileges.<HR>");
         footer();
      }
   }
   logit("Exit subroutine getDbVersion");
}

sub dbClosed {

   logit("Enter subroutine dbClosed");
   
   Header($title,$heading,$font,$fontsize,$fontcolor,$bgcolor);
   if ($object_name) {
      logit("   SQL passed to dbClosed: \n$object_name");
      runSQL($dbh,$object_name);
   } else {
      logit("   No SQL passed, displaying worksheet.");
      enterWorksheet();
   }

   logit("Exit subroutine dbClosed");

   exit;
}

sub dbStatus {

# See what status the database is in.

   my ($cursor,$sql,$dbstatus);

   logit("Enter subroutine dbStatus");

   if ($notoracle7) {
      logit("   We are Oracle8, checking database status.");
      $sql = "$copyright
SELECT
   STATUS
FROM V\$INSTANCE
";
      $cursor = $dbh->prepare($sql) or ErrorPage("Error: $DBI::errstr");
      logit("   Error from status SQL preparation.. $DBI::errstr") if ($DBI::errstr);
      $cursor->execute;
      $dbstatus = $cursor->fetchrow_array;
      $cursor->finish;
   } else {
      logit("   We are Oracle7, assuming database is open.");
      $dbstatus = "OPEN";
   }

   logit("   Database was found to be $dbstatus.");

#   if ($dbstatus ne "OPEN") {
#      dbClosed();
#   }

   logit("Exit subroutine dbStatus");

   return($dbstatus);
}

sub statsPackInstalled {

   logit("Enter subroutine statsPackInstalled");

   my ($sql,$count);

   $sql = "
SELECT
   COUNT(*) 
FROM DBA_OBJECTS
   WHERE OBJECT_NAME = 'STATSPACK'
AND OBJECT_TYPE = 'PACKAGE'
";

   $count = recordCount($dbh,$sql);

   logit("Exit subroutine statsPackInstalled");

   return($count);

}

sub createMainPage() {

   logit("Enter subroutine createMainPage");

# This sub will be called if this script is invoked without a 'database=....'
# element in the URL.  

# Get the connection strings from the tnsnames.ora file.

   my @sids = GetTNS();

# Start creating main page

   my $bgline = "<BODY BGCOLOR=$bgcolor>\n";

   if ($bgimage) {
      if ((-e "$ENV{'DOCUMENT_ROOT'}/$bgimage") && (-r "$ENV{'DOCUMENT_ROOT'}/$bgimage")) {
         logit("Background image is $ENV{'DOCUMENT_ROOT'}/$bgimage and is readable");
         $bgline = "<BODY BACKGROUND=$bgimage>\n";
      }
   }

   # Get a cookie containing the most recent connection, so it may be highlighted.

   my $recent = cookie("OracletoolRecent");
   logit("The last connection was to $recent");

print << "EOF";
Content-type: Text/html\n\n
<HTML>
  <HEAD>
    <TITLE>Oracletool v$VERSION</TITLE>
  </HEAD>
    $bgline
    <CENTER>
    <H2> 
    <FONT COLOR="$fontcolor" FACE="$font" SIZE="5">
      Oracletool v$VERSION
    </FONT>
    </H2>
    </CENTER>
    <BR><BR>
    <TABLE BGCOLOR="BLACK" WIDTH="400" CELLPADDING="1" CELLSPACING="0" BORDER="0">
      <TR>
        <TD VALIGN="TOP">
          <TABLE BGCOLOR="$cellcolor" WIDTH="100%" CELLPADDING="2" CELLSPACING="1" BORDER="0">
            <TR ALIGN="LEFT">
              <TD>
                <TABLE>
                  <TR>
                    <TD ALIGN="LEFT">
                      <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
EOF
print "                      <STRONG>Select an instance..\n" if (! $oraclenames);
print "                      <STRONG>Select or enter an instance name.</STRONG>\n" if ($oraclenames);
print <<"EOF";
                      <FORM METHOD="POST" ACTION="$scriptname">
                      <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
                      <P>
                      <SELECT NAME="database">
EOF

my $sid;
foreach $sid (@sids) {
   if ($sid eq $recent) {
      print "                <OPTION VALUE=\"$sid\" SELECTED>$sid</OPTION>\n";
   } else {
      print "                <OPTION VALUE=\"$sid\">$sid</OPTION>\n";
   }
}

print <<"EOF";
                      </SELECT>
                    </TD>
EOF
   if ($oraclenames) {
      print <<"EOF";
                  </TR>
                  <TR>
                    <TD>
                      <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
                      <INPUT TYPE="TEXT" NAME="namesdatabase" SIZE="20">
                    </TD>
EOF
   }
   print <<"EOF";
                  </TR>
                  <TR>
                    <TD ALIGN="LEFT" VALIGN="TOP">
                      <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
                      <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="FRAMEPAGE">
                      <INPUT TYPE="SUBMIT" VALUE="Connect">
                      <INPUT TYPE="CHECKBOX" NAME="expire" VALUE="Yep">Expire password cookie
                      </P>
	      </FORM>
                      <P>
                    </TD>
                  </TR>
                </TABLE>
              </TD>
            </TR>
          </TABLE>
        </TD>
      </TR>
    </TABLE>
EOF
#   Button("$scriptname?object_type=MYORACLETOOL","My Oracletool","$headingcolor");
   print <<"EOF";
  </BODY>
</HTML>
EOF

   logit("Exit subroutine createMainPage");
}

sub setTheme {

   logit("Enter subroutine setTheme");

   my ($message,$duration,$url,$cookie,$path,$bgline);

   $theme = $object_name;
   $path   = dirname($scriptname);
   
   $cookie = cookie(-name=>"OracletoolTheme",-value=>"$theme",-expires=>"+10y");
   print header(-cookie=>[$cookie]);
   $message     = "Your personal theme has been set to $theme.<BR>Oracletool will restart with a connection to instance $database.";
   $duration    = "4";
   $url         = "$scriptname?database=$database&object_type=FRAMEPAGE";

   $bgline = "<BODY BGCOLOR=$bgcolor>\n";

   if ($bgimage) {
      if ((-e "$ENV{'DOCUMENT_ROOT'}/$bgimage") && (-r "$ENV{'DOCUMENT_ROOT'}/$bgimage")) {
         logit("   Background image is $ENV{'DOCUMENT_ROOT'}/$bgimage and is readable");
         $bgline = "<BODY BACKGROUND=$bgimage>\n";
      }
   }

   print <<"EOF";
<HTML>
  <HEAD>
    <TITLE>Theme is set to $theme.</TITLE>
    <META HTTP-EQUIV="Refresh" Content="$duration;URL=$url">
  </HEAD>
   $bgline
    <FONT FACE="$font" SIZE="$fontsize" COLOR="$fontcolor">
    <CENTER>
      $message
    </CENTER
  </BODY
</HTML>
EOF

   logit("Exit subroutine setTheme");

   exit;
}

sub doProperties {

   logit("Enter subroutine doProperties");

   my $properties = cookie("OracletoolProps");

   if ($properties) {
      ($schema_cols,$fontsize,$menufontsize,$textarea_w,$textarea_h,$rowdisplay) = split (/%/, $properties);
   } else {
   # Set the variables that are not taken care of by a theme.
      $menufontsize = "2";
      $schema_cols = "5";
      $textarea_w = "80";
      $textarea_h = "20";
      $rowdisplay = "25";
   }

   logit("Exit subroutine doProperties");

}

sub setProperties {

   logit("Enter subroutine setProperties");

   my ($cookie,$properties,$message,$duration,$url,$path,$bgline);

   # Compare the selected properties with the ones set in this users
   # default theme, where applicable. If they are different, then
   # update a properties cookie. These parameters were passed in by
   # names that make no sense, in order to cut down on global variables.

   # $schema holds the value for $schema_cols.
   # $schema_cols is the number of columns wide to display the toplevel
   # schema list.
   $schema_cols = $schema;

   # $explainschema holds the value for $fontsize.
   # If not set, use value from theme.
   $fontsize = $explainschema;

   # $expire holds the value for $menufontsize.
   # If not set, default to '2'.
   $menufontsize = $expire;

   # $statement_id holds the value for TEXTAREA width
   $textarea_w = $statement_id;

   # $user holds the value for TEXTAREA height
   $textarea_h = $user;

   # $whereclause holds the value for how many rows to display.
   $rowdisplay = $whereclause;

   $properties = "$schema_cols%$fontsize%$menufontsize%$textarea_w%$textarea_h%$rowdisplay";
   $path = dirname($scriptname);

   $cookie = cookie(-name=>"OracletoolProps",-value=>"$properties",-expires=>"+10y");
   print header(-cookie=>[$cookie]);
   $message     = "Your personal Oracletool preferences have been updated.<BR>Oracletool will restart with a connection to instance $database.";
   $duration    = "4";
   $url         = "$scriptname?database=$database&object_type=FRAMEPAGE";

   $bgline = "<BODY BGCOLOR=$bgcolor>\n";

   if ($bgimage) {
      if ((-e "$ENV{'DOCUMENT_ROOT'}/$bgimage") && (-r "$ENV{'DOCUMENT_ROOT'}/$bgimage")) {
         logit("   Background image is $ENV{'DOCUMENT_ROOT'}/$bgimage and is readable");
         $bgline = "<BODY BACKGROUND=$bgimage>\n";
      }
   }

   print <<"EOF";
<HTML>
  <HEAD>
    <TITLE>Properties have been reset.</TITLE>
    <META HTTP-EQUIV="Refresh" Content="$duration;URL=$url">
  </HEAD>
  $bgline
    <FONT FACE="$font" SIZE="$fontsize" COLOR="$fontcolor">
    <CENTER>
      $message
    </CENTER
  </BODY
</HTML>
EOF

   logit("Exit subroutine setProperties");

   exit;
}

sub showProps {

   logit("Enter subroutine showProps");

   # Display a menu for selecting non-default properties for the tool.
   # These will be stored as cookies.

   message("Oracletool preferences<BR>Setting these values will override values set in any theme.<BR>Submit changes or select theme at the bottom of this screen.");

   my ($fontsizeoverride,$fontoverride,$val);

   print <<"EOF";
<FORM METHOD="POST" ACTION="$scriptname" TARGET="_top">
<TABLE BORDER=0 ALIGN=LEFT>
  <TR WIDTH=50%>
    <TD ALIGN=CENTER>
      <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
      <INPUT TYPE=HIDDEN NAME='database' VALUE='$database'>
      <INPUT TYPE=HIDDEN NAME='object_type' VALUE='SETPROPS'>
      <INPUT TYPE=SUBMIT NAME='foobar' VALUE='Submit changes'>
    </TD>
  </TR>
  <TR>
    <TD VALIGN="TOP">
      <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
      <B>
      Schema list column number:<BR>
      This sets the number of columns in the schema list table.<BR>
EOF
   # Loop through the values, in order to check the box which is the
   # value of what is set now.
      foreach $val ('3','4','5','6','7') {
         print "      <INPUT TYPE=RADIO NAME='schema' VALUE='$val'";
         if ($val == $schema_cols) {
            print " CHECKED>$val\n";
         } else {
            print " >$val\n";
         }
      }
print <<"EOF";
      <HR WIDTH='50%' ALIGN='LEFT'>
    </TD>
  </TR>
  <TR>
    <TD VALIGN="TOP">
      <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
      <B>
      Font size override:<BR>
      This will override the font size set by your theme.<BR>
EOF
   # Loop through the values, in order to check the box which is the
   # value of what is set now.
      foreach $val ('1','2','3','4','5','6','7') {
         print "<INPUT TYPE=RADIO NAME='explainschema' VALUE='$val'";
         if ($val == $fontsize) {
            print " CHECKED>$val\n";
         } else {
            print " >$val\n";
         }
      }
print <<"EOF";
      <HR WIDTH='50%' ALIGN='LEFT'>
    </TD>
  </TR>
  <TR>
    <TD VALIGN="TOP">
      <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
      <B>
      Menu button font size override:<BR>
      This will override the menu button font size set by your theme.<BR>
EOF
   # Loop through the values, in order to check the box which is the
   # value of what is set now.
      foreach $val ('1','2','3','4') {
         print "<INPUT TYPE=RADIO NAME='expire' VALUE='$val'";
         if ($val == $menufontsize) {
            print " CHECKED>$val\n";
         } else {
            print " >$val\n";
         }
      }
print <<"EOF";
      <HR WIDTH='50%' ALIGN='LEFT'>
    </TD>
  </TR>
  <TR>
    <TD VALIGN="TOP">
      <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
      <B>
      Textarea width:<BR>
      Width in characters of the SQL editing area.<BR>
EOF
      foreach $val ('30','40','50','60','70','80','100','125','150') {
         print "<INPUT TYPE=RADIO NAME='statement_id' VALUE='$val'";
         if ($val == $textarea_w) {
            print " CHECKED>$val\n";
         } else {
            print " >$val\n";
         }
      }
print <<"EOF";
      <HR WIDTH='50%' ALIGN='LEFT'>
    </TD>
  </TR>
  <TR>
    <TD VALIGN="TOP">
      <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
      <B>
      Textarea height:<BR>
      Height in characters of the SQL editing area.<BR>
EOF
      foreach $val ('5','10','15','20','25','30','35','40','45','50') {
         print "<INPUT TYPE=RADIO NAME='user' VALUE='$val'";
         if ($val == $textarea_h) {
            print " CHECKED>$val\n";
         } else {
            print " >$val\n";
         }
      }
print <<"EOF";
      <HR WIDTH='50%' ALIGN='LEFT'>
    </TD>
  </TR>
  <TR>
    <TD VALIGN="TOP">
      <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
      <B>
      Row display default:<BR>
      Number of rows to return on a table/view row display.<BR>
EOF
      foreach $val ('1','5','25','50','100','250','500','all') {
         print "<INPUT TYPE=RADIO NAME='whereclause' VALUE='$val'";
         if ($val eq $rowdisplay) {
            print " CHECKED>$val\n";
         } else {
            print " >$val\n";
         }
      }
print <<"EOF";
      <HR WIDTH='50%' ALIGN='LEFT'>
    </TD>
  </TR>
  <TR WIDTH=50%>
    <TD ALIGN=CENTER>
      <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
      <INPUT TYPE=HIDDEN NAME='database' VALUE='$database'>
      <INPUT TYPE=HIDDEN NAME='object_type' VALUE='SETPROPS'>
      <INPUT TYPE=SUBMIT NAME='foobar' VALUE='Submit changes'>
    </TD>
  </TR>
  </FORM>
  <TR>
</TABLE>
EOF

   logit("Exit subroutine showProps");

}

sub showThemes {

   logit("Enter subroutine showThemes");

   # Display all of the themes.

   my ($currenttheme,@themevars);

   $currenttheme = $theme;

   text("Select a color theme for your default.<BR>Your current theme is \"$currenttheme\".");

   foreach $theme (sort keys %themes) {
      logit("   Displaying theme $theme");
      @themevars        = @{ $themes{$theme} };
      $description      = $themevars[0]  or $description      = "undefined";
      $bgcolor          = $themevars[1]  or $bgcolor          = "undefined";
      $menuimage        = $themevars[2]  or $menuimage        = "undefined";
      $bgimage          = $themevars[3]  or $bgimage          = "undefined";
      $fontcolor        = $themevars[4]  or $fontcolor        = "undefined";
      $headingfontcolor = $themevars[5]  or $fontcolor        = "undefined";
      $infocolor        = $themevars[6]  or $infocolor        = "undefined";
      $linkcolor        = $themevars[7]  or $linkcolor        = "undefined";
      $font             = $themevars[8]  or $font             = "undefined";
      $headingfont      = $themevars[9]  or $font             = "undefined";
      $fontsize         = $themevars[10] or $fontsize         = "undefined";
      $headingcolor     = $themevars[11] or $headingcolor     = "undefined";
      $cellcolor        = $themevars[12] or $cellcolor        = "undefined";
      $bordercolor      = $themevars[13] or $bordercolor      = "undefined";

      print <<"EOF";
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD VALIGN="TOP" WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1 WIDTH=100%>
        <TR>
          <TD BGCOLOR='$bgcolor'>
            <TABLE CELLPADDING=20>
              <TH><A HREF=$scriptname?database=$database&object_type=SETTHEME&arg=$theme TARGET=_top>$theme</A></TH>
              <TR>
                <TD BGCOLOR=$bgcolor ALIGN=CENTER><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
                  <TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
                    <TR>
                      <TD VALIGN="TOP" WIDTH=100%>
                        <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1 WIDTH=100%>
                            <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Table headings</TH>
                            <TR ALIGN="CENTER">
                              <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
                               Table cells
                              </TD>
                          </TR>
                        </TABLE>
                      </TD>
                    </TR>
                  </TABLE><FONT COLOR='$linkcolor' SIZE='$fontsize' FACE='$font'><BR>link color
                </TD>
              </TR>
            </TABLE>
          </TD>
        </TR>
      </TABLE>
    </TD>
  </TR>
</TABLE>
<P>
EOF

   }

   logit("Exit subroutine showThemes");

}

sub validateIndex {

   logit("Enter subroutine validateIndex");

   my ($sql,$text,$link);

   $sql = "
VALIDATE INDEX $schema.$object_name
";

   runSQL($dbh,$sql);

   $sql = "$copyright
SELECT
   HEIGHT						\"Height\",
   TO_CHAR(BLOCKS,'999,999,999,999')			\"Blocks\",
   TO_CHAR(LF_ROWS,'999,999,999,999')			\"Leaf rows\",
   TO_CHAR(LF_BLKS,'999,999,999,999')			\"Leaf blocks\",
   TO_CHAR(DEL_LF_ROWS,'999,999,999,999')		\"Deleted leaf rows #\",
   TO_CHAR((DEL_LF_ROWS/LF_ROWS)*100,'999.99')		\"Ratio of deleted leaf rows\",
   TO_CHAR(DISTINCT_KEYS,'999,999,999,999')		\"Distinct keys #\",
   TO_CHAR(BTREE_SPACE,'999,999,999,999')		\"Total space allocated\",
   TO_CHAR(USED_SPACE,'999,999,999,999')		\"Total space used\",
   TO_CHAR(PCT_USED,'999')||'%'				\"Percent used\"
FROM INDEX_STATS
";

#   $sql = "$copyright
#SELECT
#   HEIGHT						\"Height\",
#   TO_CHAR(BLOCKS,'999,999,999,999')			\"Blocks\",
#   TO_CHAR(LF_ROWS,'999,999,999,999')			\"Leaf rows\",
#   TO_CHAR(LF_BLKS,'999,999,999,999')			\"Leaf blocks\",
#   TO_CHAR(LF_ROWS_LEN,'999,999,999,999')		\"Leaf row sum\",
#   TO_CHAR(LF_BLK_LEN,'999,999,999,999')		\"Leaf block usable space\",
#   TO_CHAR(BR_ROWS,'999,999,999,999')			\"Branch rows #\",
#   TO_CHAR(BR_BLKS,'999,999,999,999')			\"Branch blocks #\",
#   TO_CHAR(BR_ROWS_LEN,'999,999,999,999')		\"Blocks length sum\",
#   TO_CHAR(BR_BLK_LEN,'999,999,999,999')		\"Branch block usable space\",
#   TO_CHAR(DEL_LF_ROWS,'999,999,999,999')		\"Deleted leaf rows #\",
#   TO_CHAR(DEL_LF_ROWS_LEN,'999,999,999,999')		\"Deleted rows length\",
#   TO_CHAR((DEL_LF_ROWS/LF_ROWS)*100),'999.99')		\"Ratio\",
#   TO_CHAR(DISTINCT_KEYS,'999,999,999,999')		\"Distinct keys #\",
#   TO_CHAR(MOST_REPEATED_KEY,'999,999,999,999')		\"Most repeated key #\",
#   TO_CHAR(BTREE_SPACE,'999,999,999,999')		\"Total space allocated\",
#   TO_CHAR(USED_SPACE,'999,999,999,999')		\"Total space used\",
#   TO_CHAR(PCT_USED,'999')||'%'				\"Percent used\",
#   TO_CHAR(ROWS_PER_KEY,'999,999,999,999')		\"Rows per distinct key\",
#   TO_CHAR(BLKS_GETS_PER_ACCESS,'999,999,999,999')	\"Block gets per access\"
#FROM INDEX_STATS
#";

   $text = "Index statistics.";
   $link = "";
   DisplayTable($sql,$text,$link);

   $sql = "$copyright
SELECT
   REPEAT_COUNT					\"Repeat count\",
   KEYS_WITH_REPEAT_COUNT			\"Keys with repeat count\"
FROM INDEX_HISTOGRAM
";

   $text = "This table shows the number of times that one or more index keys is repeated in the table, and the number of index keys that are repeated that many times.";
   $link = "";
   DisplayTable($sql,$text,$link);

   logit("Exit subroutine validateIndex");
}

sub showIndex {

   logit("Enter subroutine showIndex");

   my ($sql,$text,$link,$foo,$partitioned);   

# Index structure
   $sql = "$copyright 
SELECT 
   TABLE_NAME					\"Table name\",
   TABLE_OWNER					\"Owner\",
   COLUMN_NAME					\"Column name\", 
   COLUMN_LENGTH				\"Column length\" 
FROM DBA_IND_COLUMNS 
   WHERE INDEX_NAME = '$object_name' 
AND INDEX_OWNER = '$schema' 
   ORDER BY COLUMN_POSITION
";
   $object_type = lc $object_type;
   $text = "Structure of $object_type $object_name";
   $link = "";
   DisplayTable($sql,$text,$link);

# General
   $sql = "$copyright
SELECT  
   A.TABLESPACE_NAME					\"Tablespace name\", 
   TO_CHAR(B.CREATED,'Month DD, YYYY - HH24:MI')        \"Date created\",
   TO_CHAR(B.LAST_DDL_TIME,'Month DD, YYYY - HH24:MI')  \"Last DDL time\",
   TO_CHAR(A.EXTENTS,'999,999,999,999')			\"Extents\", 
   TO_CHAR(A.INITIAL_EXTENT,'999,999,999,999')		\"Initial extent\", 
   TO_CHAR(A.NEXT_EXTENT,'999,999,999,999')		\"Next extent\",
   TO_CHAR(A.MAX_EXTENTS,'999,999,999,999')		\"Max extents\",
   TO_CHAR(A.BYTES,'999,999,999,999')			\"Bytes\",
   B.STATUS						\"Status\",
   C.STATUS						\"State\"
FROM DBA_SEGMENTS A, DBA_OBJECTS B, DBA_INDEXES C
   WHERE A.SEGMENT_NAME = '$object_name' 
   AND A.SEGMENT_TYPE = 'INDEX' 
   AND A.OWNER = '$schema'
   AND B.OBJECT_NAME = '$object_name'
   AND B.OBJECT_TYPE = 'INDEX'
   AND B.OWNER = '$schema'
   AND B.OWNER = C.OWNER
   AND B.OBJECT_NAME = C.INDEX_NAME
";
   $object_type = lc $object_type;
   $text = "General info: $object_type $object_name";
   $link = "";
   DisplayTable($sql,$text,$link);

# Check to see if index is partitioned, if Oracle8

   if ($notoracle7) {

      $sql = "$copyright
SELECT
   PARTITIONED
FROM DBA_INDEXES
   WHERE INDEX_NAME = '$object_name'
   AND OWNER = '$schema'
";

      $cursor=$dbh->prepare($sql);
      $cursor->execute;
      $foo = $cursor->fetchrow_array;
      $cursor->finish;
      if ($foo eq "YES") {
         $partitioned = "Yep";
      }
   }

# If partitioned, show some additional info.

   if ($partitioned) {
      $sql = "$copyright
SELECT
   PARTITION_NAME                               \"Partition name\",
   TABLESPACE_NAME                              \"Tablespace\",
   PARTITION_POSITION                           \"Position\",
   TO_CHAR(INITIAL_EXTENT,'999,999,999,999')    \"Initial\",
   TO_CHAR(NEXT_EXTENT,'999,999,999,999')       \"Next\",
   TO_CHAR(MAX_EXTENT,'999,999,999,999')        \"Max extents\",
   PCT_INCREASE                                 \"Pct increase\",
   HIGH_VALUE                                   \"High value\",
   HIGH_VALUE_LENGTH                            \"High value length\",
   LOGGING                                      \"Logging\"
FROM DBA_IND_PARTITIONS
   WHERE INDEX_NAME = '$object_name'
   AND INDEX_OWNER = '$schema'
ORDER BY PARTITION_POSITION
";

      $text = "Partitions contained in this index";
      $link = "$scriptname?database=$database&schema=$schema&object_type=INDEX+PARTITION&index_name=$object_name";
      DisplayTable($sql,$text,$link);
   }

   if (checkPriv("ANALYZE ANY")) {
      print <<"EOF";
<BR>
<FORM METHOD="GET" ACTION="$scriptname">
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
  <INPUT TYPE="HIDDEN" NAME="arg" VALUE="$object_name">
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="VALIDATEINDEX">
  <INPUT TYPE="SUBMIT" NAME="foo" VALUE="Validate index for detailed statistics.">
</FORM>
EOF
   }

   logit("Exit subroutine showIndex");

}

sub showIndexPart {

   logit("Enter subroutine showIndexPart");

   my ($sql,$cursor,$isanalyzed,$text,$link,$infotext,$index_name);

   $index_name = $query->param('index_name');

   $sql = "$copyright
SELECT
   PARTITION_NAME                               \"Partition name\",
   INDEX_NAME                                   \"Index name\",
   INDEX_OWNER                                  \"Owner\",
   TABLESPACE_NAME                              \"Tablespace\",
   PARTITION_POSITION                           \"Position\",
   TO_CHAR(INITIAL_EXTENT,'999,999,999,999')    \"Initial\",
   TO_CHAR(NEXT_EXTENT,'999,999,999,999')       \"Next\",
   TO_CHAR(MAX_EXTENT,'999,999,999,999')        \"Max extents\",
   PCT_INCREASE                                 \"Pct increase\",
   HIGH_VALUE                                   \"High value\",
   HIGH_VALUE_LENGTH                            \"High value length\",
   LOGGING                                      \"Logging\"
FROM DBA_IND_PARTITIONS
   WHERE PARTITION_NAME = '$object_name'
   AND INDEX_NAME = '$index_name'
   AND INDEX_OWNER = '$schema'
";

   $object_type = lc $object_type;
   $text = "General info: $object_type $object_name";
   $link = "";
   DisplayTable($sql,$text,$link);

   logit("Exit subroutine showIndexPart");

}

sub showTablePart {

   logit("Enter subroutine showTablePart");

   my ($sql,$cursor,$isanalyzed,$text,$link,$infotext,$table_name);

   $table_name = $query->param('table_name');

# General info

   $sql = "$copyright
SELECT 
   PARTITION_NAME				\"Partition name\",
   TABLE_NAME					\"Table name\",
   TABLE_OWNER					\"Owner\",
   TABLESPACE_NAME				\"Tablespace\",
   PARTITION_POSITION				\"Position\",
   TO_CHAR(INITIAL_EXTENT,'999,999,999,999')	\"Initial\",
   TO_CHAR(NEXT_EXTENT,'999,999,999,999')	\"Next\",
   TO_CHAR(MAX_EXTENT,'999,999,999,999')	\"Max extents\",
   PCT_INCREASE					\"Pct increase\",
   HIGH_VALUE					\"High value\",
   HIGH_VALUE_LENGTH				\"High value length\",
   LOGGING					\"Logging\"
FROM DBA_TAB_PARTITIONS
   WHERE PARTITION_NAME = '$object_name'
   AND TABLE_NAME = '$table_name'
   AND TABLE_OWNER = '$schema'
";

   $object_type = lc $object_type;
   $text = "General info: $object_type $object_name";
   $link = "";
   DisplayTable($sql,$text,$link);

# Check to see if partition has been analyzed.

   $sql = "$copyright
SELECT 
   DISTINCT LAST_ANALYZED
FROM DBA_TAB_PARTITIONS
   WHERE PARTITION_NAME = '$object_name'
   AND TABLE_OWNER = '$schema'
";

   $cursor=$dbh->prepare($sql);
   logit("   Error: $DBI::errstr") if $DBI::errstr;
   $cursor->execute;
   $isanalyzed = $cursor->fetchrow_array;
   logit("   Isanalyzed for partition $schema.$object_name is $isanalyzed");
   $cursor->finish;

   if ($isanalyzed) {

      $sql = "$copyright
SELECT
   TO_CHAR((BLOCKS / (EMPTY_BLOCKS+BLOCKS)) *100,'999.99')||'%'      \"Percent used\",
   TO_CHAR(NUM_ROWS,'999,999,999,999')                          \"Row count\",
   TO_CHAR(BLOCKS,'999,999,999,999')                            \"Blocks\",
   TO_CHAR(EMPTY_BLOCKS,'999,999,999,999')                      \"Empty blocks\",
   TO_CHAR(AVG_SPACE,'999,999,999,999')                         \"Average space\",
   TO_CHAR(AVG_ROW_LEN,'999,999,999,999')                       \"Average row length\",
   TO_CHAR(CHAIN_CNT,'999,999,999,999')                         \"Chain count\",
   TO_CHAR(LAST_ANALYZED,'Month DD, YYYY - HH24:MI')			\"Last analyzed\"
FROM DBA_TAB_PARTITIONS
   WHERE PARTITION_NAME = '$object_name'
   AND TABLE_OWNER = '$schema'
";

      $text = "Analyzation info: $object_type $object_name";
      $link = "";
      DisplayTable($sql,$text,$link);
   } else {
      message("Partition has never been analyzed. Extended info will not be shown.");
   }

   logit("Exit subroutine showTablePart");

}

sub showCluster {

   logit("Enter subroutine showCluster");

   my ($sql,$text,$link,$infotext);

   $sql = "$copyright
SELECT
   TABLESPACE_NAME					\"Tablespace name\",
   TO_CHAR(INITIAL_EXTENT,'999,999,999,999')		\"Initial extent\",
   TO_CHAR(NEXT_EXTENT,'999,999,999,999')		\"Next extent\",
   TO_CHAR(MAX_EXTENTS,'999,999,999,999')		\"Max extents\",
   CLUSTER_TYPE						\"Cluster type\",
   FUNCTION						\"Function\",
   INSTANCES						\"Instances\",
   SINGLE_TABLE						\"Single table\"
FROM DBA_CLUSTERS 
   WHERE CLUSTER_NAME = '$object_name'
   AND OWNER = '$schema'
";

   logit ("   $sql");

   $text = "General info: Cluster $object_name";
   $link = "";
   DisplayTable($sql,$text,$link);

   $sql = "$copyright
SELECT
   TABLE_NAME						\"Table_name\",
   TO_CHAR(INITIAL_EXTENT,'999,999,999,999')		\"Initial extent\",
   TO_CHAR(NEXT_EXTENT,'999,999,999,999')		\"Next extent\",
   TO_CHAR(MAX_EXTENTS,'999,999,999,999')		\"Max extents\"
FROM DBA_TABLES
   WHERE CLUSTER_NAME = '$object_name'
   AND OWNER = '$schema'
";

   $text = "Tables belonging to cluster $object_name";
   $infotext = "No tables belong to cluster $object_name";
   $link = "$scriptname?database=$database&schema=$schema&object_type=TABLE";
   DisplayTable($sql,$text,$link,$infotext);
    
   logit("Exit subroutine showCluster");

}
   

sub showTable {

   logit("Enter subroutine showTable");

   my ($sql,$text,$link,$infotext,$cursor,$isanalyzed,$partitioned,$grantcount,$foo);
   my (@columns,$cols,$constraint_name,$column_name,$status,$index_name,$tablespace_name);
   my ($indexes,$cursor1,$sql1,$uniqueness,$initial_extent,$next_extent,$max_extents);
   my ($r_owner,$r_constraint_name,$count,$r_table_name,$iot_type,$temporary,$index_type);

   print <<"EOF";
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 cellpadding=5 cellspacing=1>
        <TR>
          <TD BGCOLOR=$headingcolor>
            <TABLE BORDER=0 CELLPADDING=0 CELLSPACING=0>
              <TR>
                <TD ALIGN=CENTER>
                  <FORM METHOD="GET" ACTION="$scriptname">
                    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
                    <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
                    <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="TABLEROWS">
                    <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
                    <INPUT TYPE="HIDDEN" NAME="arg" VALUE="$object_name">
                    <INPUT TYPE="SUBMIT" NAME="tablerows" VALUE="Display $rowdisplay rows of this table">
                </TD>
              </TR>
              <TR>
                <TD ALIGN=CENTER><FONT COLOR=$fontcolor SIZE=$fontsize><B><I>where</I></B></FONT></TD>
              </TR>
              <TR>
                <TD ALIGN=CENTER>
                    <INPUT TYPE="TEXT" SIZE=30 NAME="whereclause">
                </TD> 
                  </FORM>
              </TR>
            </TABLE>
          </TD>
        </TR>
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF

$grantcount = showGrantButton();

unless ($grantcount) {
   print "<BR>";
}

if ($oracle9i || $oracle10 || $oracle11) {

print <<"EOF";
<TABLE BORDER=0 CELLPADDING=5 CELLSPACING=1>
  <TR>
    <TD ALIGN=CENTER>
      <FORM METHOD=POST ACTION="$scriptname" target="_blank">
        <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
        <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
        <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="OBJECTDDL">
        <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
        <INPUT TYPE="HIDDEN" NAME="object_name" VALUE="$object_name">
        <INPUT TYPE="HIDDEN" NAME="objecttype" VALUE="TABLE">
        <INPUT TYPE="HIDDEN" NAME="everything" VALUE="Yep">
        <INPUT TYPE="SUBMIT" NAME="foo" VALUE="Generate DDL">
      </FORM>
    </TD>
    <TD ALIGN=CENTER>
      <FORM METHOD=POST ACTION=$scriptname>
        <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
        <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
        <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="OBJECTFRAGMAP">
        <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
        <INPUT TYPE="HIDDEN" NAME="arg" VALUE="$object_name">
        <INPUT TYPE="SUBMIT" NAME="foo" VALUE="Extent mapping">
      </FORM>
    </TD>
  </TR>
</TABLE>
EOF
} else {
   print <<"EOF";
      <FORM METHOD=POST ACTION=$scriptname>
        <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
        <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
        <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="OBJECTFRAGMAP">
        <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
        <INPUT TYPE="HIDDEN" NAME="arg" VALUE="$object_name">
        <INPUT TYPE="SUBMIT" NAME="foo" VALUE="Extent mapping">
      </FORM>
EOF
}

# Table comments

   $sql = "$copyright
SELECT
   COMMENTS                                      \"Comment\"
   FROM DBA_TAB_COMMENTS
WHERE TABLE_NAME = '$object_name'
AND OWNER = '$schema'
";

$object_type = lc $object_type;
$text = "Comment on $object_type $object_name";
$link = "";
DisplayTable($sql,$text,$link) if( recordCount($dbh,$sql) );

# Table structure

   $sql = "$copyright
SELECT
   A.COLUMN_NAME                                 \"Column name\",
   A.DATA_TYPE                                   \"Type\",
   A.DATA_LENGTH                                 \"Length\",
   A.DATA_PRECISION                              \"Precision\",
   B.DATA_DEFAULT                                \"Default\",
   TO_CHAR(A.LAST_ANALYZED,'Month DD, YYYY - HH24:MI')     \"Last analyzed\",
   C.COMMENTS                                    \"Comments\"
   FROM
          (SELECT
             TABLE_NAME,
             OWNER,
             COLUMN_ID,
             COLUMN_NAME,
             DATA_TYPE,
             DATA_LENGTH,
             DATA_PRECISION,
             LAST_ANALYZED
             FROM DBA_TAB_COLUMNS
          WHERE (TABLE_NAME = '$object_name')
          AND (OWNER = '$schema')
          AND (DATA_TYPE <> 'NUMBER')
           UNION
           SELECT
             TABLE_NAME,
             OWNER,
             COLUMN_ID,
             COLUMN_NAME,
             DATA_TYPE,
             DATA_PRECISION,
             DATA_SCALE,
             LAST_ANALYZED
             FROM DBA_TAB_COLUMNS
           WHERE (TABLE_NAME = '$object_name')
           AND (OWNER = '$schema')
           AND (DATA_TYPE = 'NUMBER')
          ) A,
        DBA_TAB_COLUMNS B,
          (SELECT
             TABLE_NAME,
             OWNER,
             COLUMN_NAME,
             COMMENTS
             FROM DBA_COL_COMMENTS
          WHERE (TABLE_NAME = '$object_name')
          AND (OWNER = '$schema')
         ) C
   WHERE (A.TABLE_NAME = B.TABLE_NAME)
   AND (B.TABLE_NAME = C.TABLE_NAME)
   AND (A.OWNER = B.OWNER)
   AND (B.OWNER = C.OWNER)
   AND (A.COLUMN_ID = B.COLUMN_ID)
   AND (A.COLUMN_NAME = C.COLUMN_NAME)
ORDER BY b.COLUMN_ID
";

   $object_type = lc $object_type;
   $text = "Structure of $object_type $object_name";
   $link = "";
   DisplayTable($sql,$text,$link);

# Check to see if table has been analyzed.

   $sql = "$copyright
SELECT 
   DISTINCT LAST_ANALYZED
FROM DBA_TAB_COLUMNS
   WHERE TABLE_NAME = '$object_name'
   AND OWNER = '$schema'
";

   $cursor=$dbh->prepare($sql);
   $cursor->execute;
   $isanalyzed = $cursor->fetchrow_array;
   $cursor->finish;

# If the table has been analyzed, show some additional information

   if ($isanalyzed) {

      $sql = "$copyright
SELECT 
   TO_CHAR((BLOCKS / (EMPTY_BLOCKS+BLOCKS)) *100,'999.99')||'%'	\"Percent used\",
   TO_CHAR(NUM_ROWS,'999,999,999,999')				\"Row count\",
   TO_CHAR(BLOCKS,'999,999,999,999')				\"Blocks\",
   TO_CHAR(EMPTY_BLOCKS,'999,999,999,999')			\"Empty blocks\",
   TO_CHAR(AVG_SPACE,'999,999,999,999')				\"Average space\",
   TO_CHAR(AVG_ROW_LEN,'999,999,999,999')			\"Average row length\",
   TO_CHAR(CHAIN_CNT,'999,999,999,999')				\"Chain count\"
FROM DBA_TABLES 
   WHERE TABLE_NAME = '$object_name'
   AND OWNER = '$schema'
";

      $text = "Analyzation info: $object_type $object_name";
      $link = "";
      DisplayTable($sql,$text,$link);
   } else {
      message("Table has never been analyzed. Extended info will not be shown.");
   }

# Gather some info for later queries
# These can be used to determine what 
# type of table we are dealing with.
# PARTITIONED: YES/NO
# IOT_TYPE: IOT/NULL
# TEMPORARY: Y/N

   if ($notoracle7) {
      $sql = "$copyright
SELECT
   PARTITIONED,
   IOT_TYPE,
   TEMPORARY
FROM DBA_TABLES
   WHERE TABLE_NAME = '$object_name'
   AND OWNER = '$schema'
";
      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      ($partitioned,$iot_type,$temporary) = $cursor->fetchrow_array;
      $cursor->finish;
   }

   if (defined $iot_type && $iot_type eq "IOT") {

      message("Table $object_name is an Index Organized Table.");

   } else {

# General info

      $sql = "$copyright
SELECT 
   A.TABLESPACE_NAME					\"Tablespace\", 
   TO_CHAR(B.CREATED,'Month DD, YYYY - HH24:MI')	\"Date created\",
   TO_CHAR(B.LAST_DDL_TIME,'Month DD, YYYY - HH24:MI')	\"Last DDL time\",
   TO_CHAR(A.EXTENTS,'999,999,999,999')			\"Extents\", 
   TO_CHAR(A.INITIAL_EXTENT,'999,999,999,999')		\"Initial extent\", 
   TO_CHAR(A.NEXT_EXTENT,'999,999,999,999')		\"Next extent\", 
   TO_CHAR(A.MAX_EXTENTS,'999,999,999,999')		\"Max extents\",
   TO_CHAR(A.BYTES,'999,999,999,999')			\"Bytes\",
   A.PCT_INCREASE					\"% increase\",
   DECODE(C.CACHE,
		'    Y','Yes',
                '    N','No')				\"Cache?\"
FROM DBA_SEGMENTS A, DBA_OBJECTS B, DBA_TABLES C
   WHERE A.SEGMENT_NAME = '$object_name' 
   AND A.SEGMENT_TYPE = 'TABLE' 
   AND A.OWNER = '$schema'
   AND B.OBJECT_NAME = '$object_name'
   AND B.OBJECT_TYPE = 'TABLE'
   AND B.OWNER = '$schema'
   AND C.TABLE_NAME = '$object_name'
   AND C.OWNER = '$schema'
";

      $object_type = lc $object_type;
      $text = "General info: $object_type $object_name";
      $link = "$scriptname?database=$database&object_type=TSINFO";
      DisplayTable($sql,$text,$link);

   }

# Check to see if table is partitioned, if Oracle8

   if ($partitioned) {
      
      $sql = "$copyright
SELECT
   PARTITIONED
FROM DBA_TABLES
   WHERE TABLE_NAME = '$object_name'
   AND OWNER = '$schema'
";

      $cursor=$dbh->prepare($sql);
      $cursor->execute;
      $foo = $cursor->fetchrow_array;
      $cursor->finish;
      if ($foo eq "YES") {
         $partitioned = "Yep";
      }
   }

# If partitioned, show some additional info.

   if ($partitioned) {
      $sql = "$copyright
SELECT
   PARTITION_NAME                               \"Partition name\",
   TABLESPACE_NAME                              \"Tablespace\",
   PARTITION_POSITION                           \"Position\",
   TO_CHAR(INITIAL_EXTENT,'999,999,999,999')    \"Initial\",
   TO_CHAR(NEXT_EXTENT,'999,999,999,999')       \"Next\",
   TO_CHAR(MAX_EXTENT,'999,999,999,999')        \"Max extents\",
   TO_CHAR(NUM_ROWS,'999,999,999,999')          \"Num rows\",
   PCT_INCREASE                                 \"Pct increase\",
   HIGH_VALUE                                   \"High value\",
   HIGH_VALUE_LENGTH                            \"High value length\",
   LOGGING                                      \"Logging\"
FROM DBA_TAB_PARTITIONS
   WHERE TABLE_NAME = '$object_name'
   AND TABLE_OWNER = '$schema'
ORDER BY PARTITION_POSITION
";

      $text = "Partitions contained in this table";
      $link = "$scriptname?database=$database&schema=$schema&object_type=TABLE+PARTITION&table_name=$object_name";
      DisplayTable($sql,$text,$link);
   }

# Show primary key (if)

   $sql = "$copyright
SELECT 
   CONSTRAINT_NAME				\"Constraint name\",
   STATUS					\"Status\"
FROM DBA_CONSTRAINTS 
   WHERE  CONSTRAINT_TYPE = 'P' 
AND TABLE_NAME = '$object_name' 
AND OWNER = '$schema'
";
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   (($constraint_name,$status) = $cursor->fetchrow);
   $cursor->finish;
   if ($constraint_name) {
      $sql = "$copyright
SELECT COLUMN_NAME
   FROM DBA_CONS_COLUMNS
WHERE CONSTRAINT_NAME = '$constraint_name'
AND OWNER = '$schema'
   ORDER BY POSITION
";
      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      while ($column_name = $cursor->fetchrow_array) {
         push @columns, $column_name;
      }
      $cursor->finish;
      if ($#columns > 0) {
         $cols = join(",", @columns);
         $cols =~ s/^,//;
      } else {
         $cols = $columns[0];
      }
      text("Primary key");
   print <<"EOF";
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 cellpadding=2 cellspacing=1>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Constraint name</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Status</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Column(s)</TH>
        <TR ALIGN=LEFT>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A href=$scriptname?database=$database&schema=$schema&object_type=INDEX&arg=$constraint_name>$constraint_name</A></TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$status</TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$cols</TD>
        </TR>
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF
   } else {
      message("This table has no primary key.");
   }

# Count indexes

   $sql = "$copyright
SELECT COUNT(*) 
   FROM DBA_INDEXES
WHERE TABLE_NAME = '$object_name'
   AND OWNER = '$schema'
";
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   while ($index_name = $cursor->fetchrow_array) {
      $indexes++;
   }
   $cursor->finish;
   
   if ($indexes) {

      text("Indexes");

      if ($oracle7) {
         print <<"EOF";
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 cellpadding=2 cellspacing=1>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Index name</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Status</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Column(s)</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Tablespace name</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Unique?</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Initial</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Next</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Max</TH>
EOF
         $sql = "$copyright
SELECT 
   INDEX_NAME					\"Index name\",
   STATUS					\"Status\",
   TABLESPACE_NAME				\"Tablespace name\",
   DECODE(UNIQUENESS,
      'UNIQUE','Yes',
      'NONUNIQUE','No')				\"Unique?\",
   TO_CHAR(INITIAL_EXTENT,'999,999,999,999')	\"Initial extent\",
   TO_CHAR(NEXT_EXTENT,'999,999,999,999')	\"Next extent\",
   TO_CHAR(MAX_EXTENTS,'999,999,999,999')	\"Max extents\"
   FROM DBA_INDEXES
WHERE TABLE_NAME = '$object_name'
   AND OWNER = '$schema'
";
         $cursor = $dbh->prepare($sql);
         $cursor->execute;
         while (($index_name,$status,$tablespace_name,$uniqueness,$initial_extent,$next_extent,$max_extents) = $cursor->fetchrow) {
            undef @columns;
            $indexes++;
            $sql1 = "$copyright
SELECT COLUMN_NAME
   FROM DBA_IND_COLUMNS
WHERE INDEX_NAME = '$index_name'
AND INDEX_OWNER = '$schema'
   ORDER BY COLUMN_POSITION
";
            $cursor1 = $dbh->prepare($sql1);
            $cursor1->execute;
            while ($column_name = $cursor1->fetchrow_array) {
               push @columns, $column_name;
            }
            $cursor1->finish;
            if ($#columns > 0) {
               $cols = join(",", @columns);
               $cols =~ s/^,//;
            } else {
               $cols = $columns[0];
            }
            print <<"EOF";
        <TR ALIGN=LEFT>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A href=$scriptname?database=$database&schema=$schema&object_type=INDEX&arg=$index_name>$index_name</A></TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$status</TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$cols</TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$tablespace_name</TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$uniqueness</TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$initial_extent</TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$next_extent</TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$max_extents</TD>
        </TR>
EOF
         }
         print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF
      }

      if ($notoracle7) {
         print <<"EOF";
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 cellpadding=2 cellspacing=1>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Index name</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Index type</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Status</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Column(s)</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Tablespace name</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Unique?</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Initial</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Next</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Max</TH>
EOF
         $sql = "$copyright
SELECT 
   INDEX_NAME					\"Index name\",
   INDEX_TYPE					\"Index type\",
   STATUS					\"Status\",
   TABLESPACE_NAME				\"Tablespace name\",
   DECODE(UNIQUENESS,
      'UNIQUE','Yes',
      'NONUNIQUE','No')				\"Unique?\",
   TO_CHAR(INITIAL_EXTENT,'999,999,999,999')	\"Initial extent\",
   TO_CHAR(NEXT_EXTENT,'999,999,999,999')	\"Next extent\",
   TO_CHAR(MAX_EXTENTS,'999,999,999,999')	\"Max extents\"
   FROM DBA_INDEXES
WHERE TABLE_NAME = '$object_name'
   AND OWNER = '$schema'
";
         $cursor = $dbh->prepare($sql);
         $cursor->execute;
         while (($index_name,$index_type,$status,$tablespace_name,$uniqueness,$initial_extent,$next_extent,$max_extents) = $cursor->fetchrow) {
            undef @columns;
            $indexes++;
            $sql1 = "$copyright
SELECT COLUMN_NAME
   FROM DBA_IND_COLUMNS
WHERE INDEX_NAME = '$index_name'
AND INDEX_OWNER = '$schema'
   ORDER BY COLUMN_POSITION
";
            $cursor1 = $dbh->prepare($sql1);
            $cursor1->execute;
            while ($column_name = $cursor1->fetchrow_array) {
               push @columns, $column_name;
            }
            $cursor1->finish;
            if ($#columns > 0) {
               $cols = join(",", @columns);
               $cols =~ s/^,//;
            } else {
               $cols = $columns[0];
            }
            print <<"EOF";
        <TR ALIGN=LEFT>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A href=$scriptname?database=$database&schema=$schema&object_type=INDEX&arg=$index_name>$index_name</A></TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$index_type</TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$status</TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$cols</TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$tablespace_name</TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$uniqueness</TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$initial_extent</TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$next_extent</TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$max_extents</TD>
        </TR>
EOF
         }
         print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF
      }
   } else {
      message("This table has no indexes");
   }

# Show column constraints (if)

   $sql = "$copyright
SELECT 
   CONSTRAINT_NAME				\"Constraint name\", 
   SEARCH_CONDITION				\"Search condition\", 
   STATUS					\"Status\" 
FROM DBA_CONSTRAINTS 
   WHERE CONSTRAINT_TYPE NOT IN ('P','R')
AND TABLE_NAME = '$object_name' 
AND OWNER = '$schema'
   ORDER BY TABLE_NAME, CONSTRAINT_NAME
";
   $text = "Column constraints";
   $link = "";
   $infotext = "This table has no column constraints.";
   DisplayTable($sql,$text,$link,$infotext);

# Show foreign key constraints (if)

   $count = "";

   $sql = "$copyright
SELECT 
   COUNT(*)
FROM DBA_CONSTRAINTS
   WHERE CONSTRAINT_TYPE = 'R'
   AND OWNER = '$schema'
   AND TABLE_NAME = '$object_name'
";
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $count = $cursor->fetchrow_array;
   $cursor->finish;

   if ($count) {
      text("Foreign key constraints");
      print <<"EOF";
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 cellpadding=2 cellspacing=1>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Constraint name</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Status</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Column(s)</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Ref owner</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Ref table</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Ref constraint</TH>
EOF
      $sql = "$copyright
SELECT
   CONSTRAINT_NAME,
   STATUS,
   R_OWNER,
   R_CONSTRAINT_NAME
FROM DBA_CONSTRAINTS
   WHERE CONSTRAINT_TYPE = 'R'
   AND OWNER = '$schema'
   AND TABLE_NAME = '$object_name'
";
      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      while (($constraint_name,$status,$r_owner,$r_constraint_name) = $cursor->fetchrow_array) {
# Add the columns
         $sql1 = "$copyright
   SELECT
COLUMN_NAME
   FROM DBA_CONS_COLUMNS
WHERE OWNER = '$schema'
AND CONSTRAINT_NAME = '$constraint_name'
";
         $cursor1 = $dbh->prepare($sql1);
         $cursor1->execute;
         undef @columns;
         while ($column_name = $cursor1->fetchrow_array) {
            push @columns, $column_name;
         }
         $cursor1->finish;
         if ($#columns > 0) {
            $cols = join(",", @columns);
            $cols =~ s/^,//;
         } else {
            $cols = $columns[0];
         }
# Get the referenced table name 
         $sql1 = "$copyright
SELECT
   TABLE_NAME
FROM DBA_CONSTRAINTS
   WHERE OWNER = '$r_owner'
   AND CONSTRAINT_NAME = '$r_constraint_name'
";
         $cursor1 = $dbh->prepare($sql1);
         $cursor1->execute;
         $r_table_name = $cursor1->fetchrow_array;
         $cursor1->finish;
         print <<"EOF";
        <TR ALIGN=LEFT>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$constraint_name</TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$status</TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$cols</TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$r_owner</TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$r_table_name</TD>
          <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$r_constraint_name</TD>
        </TR>
EOF
      }
      print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF
   } else {
      message("This table has no foreign key constraints.");
   }

# Foreign keys referencing this table (if)

   $sql = "$copyright
SELECT
   CONSTRAINT_NAME				\"Child constraint name\",
   OWNER					\"Child owner\",
   TABLE_NAME					\"Child table name\",
   STATUS					\"Status\",
   R_CONSTRAINT_NAME				\"Local constraint name\"
FROM DBA_CONSTRAINTS
   WHERE R_OWNER = '$schema'
   AND R_CONSTRAINT_NAME IN 
   ( SELECT
        CONSTRAINT_NAME
     FROM DBA_CONSTRAINTS
        WHERE TABLE_NAME = '$object_name'
        AND OWNER = '$schema')
";

   $text = "Foreign key constraints referencing $object_name";
   $link = "";
   $infotext = "There are no foreign key constraints referencing this table.";
   DisplayTable($sql,$text,$link,$infotext);

   $sql = "$copyright
SELECT
   SYNONYM_NAME			\"Synonym name\",
   OWNER			\"Owner\",
   DB_LINK			\"DB link\"
FROM DBA_SYNONYMS
   WHERE TABLE_NAME = '$object_name'
   AND TABLE_OWNER = '$schema'
";

   $text = "Synonyms pointing to this table.";
   $link = "";
   $infotext = "There are no synonyms pointing to this table.";
   DisplayTable($sql,$text,$link,$infotext);
   

   $sql = "$copyright
SELECT 
   TRIGGER_NAME			\"Trigger name\",
   TRIGGERING_EVENT		\"Event\",
   WHEN_CLAUSE			\"When clause\"
FROM DBA_TRIGGERS
   WHERE TABLE_NAME = '$object_name'
   AND OWNER = '$schema'
";
   $text = "Triggers";
   $link = "$scriptname?database=$database&schema=$schema&object_type=TRIGGER";
   $infotext = "This table has no triggers.";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine showTable");

}

sub userDDL {

   logit("Enter subroutine userDDL");

# This sub generates DDL to recreate a user.
# This sub needs to updated for Oracle8 / 8i

   my ($sql,$cursor,$password,$default_tablespace,$temporary_tablespace,$profile);
   my ($max_bytes,$tablespace_name,$granted_role,$admin_option,$default_role,$ddl);
   my ($privilege,$owner,$table_name,$grantable,$grantor,$sql1,$cursor1,@default_roles);
   my ($roles);

   $sql = "$copyright
SELECT 
   PASSWORD,
   DEFAULT_TABLESPACE,
   TEMPORARY_TABLESPACE,
   PROFILE
FROM DBA_USERS 
   WHERE USERNAME = '$schema'
";   

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   ($password,$default_tablespace,$temporary_tablespace,$profile) = $cursor->fetchrow_array;
   $cursor->finish;

   print <<"EOF";
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TR>
          <TD BGCOLOR='$cellcolor'>
            <PRE>
EOF

# Put in some remarks

   $ddl  = "/*\nDDL generated by Oracletool v$VERSION\n";
   $ddl .= "for user $schema \n*/\n\n";
   
# Create the SQL

   $ddl .= "
CREATE USER $schema
   IDENTIFIED BY VALUES '$password'
   DEFAULT TABLESPACE $default_tablespace
   TEMPORARY TABLESPACE $temporary_tablespace
   PROFILE $profile;

";

# Add quotas

   $sql = "$copyright
SELECT 
   MAX_BYTES,
   TABLESPACE_NAME
FROM DBA_TS_QUOTAS
   WHERE USERNAME = '$schema'
";

   $cursor=$dbh->prepare($sql);
   $cursor->execute;
   while (($max_bytes,$tablespace_name) = $cursor->fetchrow_array) {
      if ($max_bytes eq "-1") {
         $max_bytes = "UNLIMITED";
      }
      $ddl .= "
ALTER USER $schema QUOTA $max_bytes ON $tablespace_name;";
   }
   $cursor->finish;

# Add grants
# Roles first

   $sql = "$copyright
SELECT 
   GRANTED_ROLE,
   ADMIN_OPTION,
   DEFAULT_ROLE
FROM DBA_ROLE_PRIVS
   WHERE GRANTEE = '$schema'
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   while (($granted_role,$admin_option,$default_role) = $cursor->fetchrow_array) {
      $ddl .= "
GRANT $granted_role TO $schema";
      if ($admin_option eq "YES") {
         $ddl .= " WITH ADMIN OPTION;";
      } else {
         $ddl .= ";";
      }
      if ($default_role eq "YES") {
         push @default_roles, $granted_role;
      }
   }
   $cursor->finish;
   if (@default_roles) {
      $roles = join(",",@default_roles);
      $ddl .= "\nALTER USER $schema DEFAULT ROLE $roles;";
   }

# Explicit system privileges

   $sql = "$copyright
SELECT 
   PRIVILEGE,
   ADMIN_OPTION
FROM DBA_SYS_PRIVS
   WHERE GRANTEE = '$schema'
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   while (($privilege,$admin_option) = $cursor->fetchrow_array) {
            $ddl .= "
GRANT $privilege TO $schema";
      if ($admin_option eq "YES") {
         $ddl .= " WITH ADMIN OPTION;";
      } else {
         $ddl .= ";";
      }
   }

   print "$ddl\n";

# Explicit object privileges

   $sql = "$copyright
SELECT DISTINCT GRANTOR
   FROM DBA_TAB_PRIVS 
WHERE GRANTEE = '$schema'
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   while ($grantor = $cursor->fetchrow_array) {
      print "\n/* Grants from $grantor */\n\n";
      print "CONNECT $grantor/password\n\n";
      $sql1 = "$copyright
SELECT 
   PRIVILEGE,
   OWNER,
   TABLE_NAME,
   GRANTABLE
FROM DBA_TAB_PRIVS
   WHERE GRANTOR = '$grantor'
   AND GRANTEE = '$schema'
   ORDER BY TABLE_NAME
";

      $cursor1 = $dbh->prepare($sql1);
      $cursor1->execute;
      while (($privilege,$owner,$table_name,$grantable) = $cursor1->fetchrow) {
         print "GRANT $privilege ON $owner.$table_name TO $schema";
         if ($grantable eq "YES") {
            print " WITH GRANT OPTION;\n";
         } else {
            print ";\n";
         }
      }
      $cursor1->finish;
   }
   $cursor->finish;
   

# finish the HTML

print <<"EOF";
            </PRE>
          </TD>
        </TR>
     </TABLE>
    </TD>
  </TR>
</TABLE>
EOF

   logit("Exit subroutine userDDL");

}

sub Describe {

   logit("Enter subroutine Describe");

   my ($sql,$moresql,$text,$link,$infotext); 
   my ($cursor,$object_type);

   my $object_name = shift;

# Get owner if one is specified

   if ($object_name =~ /\./) {
      logit("   Object requested has schema name prepended.");
      ($schema, $object_name) = split(/\./,$object_name);
      $schema = uc($schema);
      $moresql = "AND OWNER = '$schema'";
   } else {
      $schema = uc($schema);
      $moresql = "AND OWNER = '$schema'";
   }
   $object_name = uc($object_name);

   logit("   Describing object $schema.$object_name");

   $sql = "$copyright
SELECT
   OBJECT_TYPE
FROM DBA_OBJECTS WHERE
   OBJECT_NAME = '$object_name'
   $moresql
";
  
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $object_type = $cursor->fetchrow_array;
   $cursor->finish;

   if ($object_type) {
      logit("   Object type is $object_type");
   } else {
      logit("   Object was not found.");
      logit("   Checking for a public synonym.");
      $sql = "$copyright
SELECT
   OBJECT_TYPE
FROM DBA_OBJECTS WHERE
   OBJECT_NAME = '$object_name'
   AND OWNER = 'PUBLIC'
";
      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      $object_type = $cursor->fetchrow_array;
      $cursor->finish;
      if ($object_type) {
         $schema = "PUBLIC";
      }
   }

   if ($object_type eq "SYNONYM") {

       logit("   Object $schema.$object_name is a synonym.");
       $sql = "
SELECT
   TABLE_OWNER,
   TABLE_NAME
FROM DBA_SYNONYMS
   WHERE SYNONYM_NAME = '$object_name'
   AND OWNER = '$schema'
";

      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      ($schema,$object_name) = $cursor->fetchrow_array;
      $moresql = "AND OWNER = UPPER('$schema')";
      $cursor->finish;
   }

   $sql = "$copyright
SELECT 
   COLUMN_NAME			\"Column name\",
   DECODE(
      NULLABLE,
         'N','Not Null',
         'Y',''
   )				\"Null?\",
   DATA_TYPE			\"Type\",
   DATA_LENGTH			\"Data length\",
   DATA_PRECISION		\"Precision\"
FROM 
   DBA_TAB_COLUMNS
WHERE TABLE_NAME = '$object_name'
   $moresql
ORDER BY COLUMN_ID
";

   $text = "Description of $schema.$object_name";
   $link = "";
   $infotext = "Object to be described does not exist";
   my $err = DisplayTable($sql,$text,$link,$infotext);

   print "<BR><HR WIDTH=\"10%\"><BR>\n";

   logit("Exit subroutine Describe");

}

sub objectSearch {

   logit("Enter subroutine objectSearch");

   my ($sql,$text,$link,$infotext,$moresql,$count);
   my ($obj_name,$object_type,$owner,$object_id);
   my ($object_found,$filenum,$block_id);

# Search for an object in the entire database

# Check for a null value

   if ($object_name eq "") {
      message("You must enter an object name!\n");
      Footer();
      exit;
   } else {
      $object_name = uc($object_name);
   }
  
   if ($object_name =~ /,/) {
# Search for an object based on FILE#, BOCK_ID
      ($filenum,$block_id) = split(",",$object_name);
      logit("   Filenum is $filenum, Block ID is $block_id");
      $sql = "
SELECT
   SEGMENT_TYPE					\"Object type\",
   SEGMENT_NAME					\"Object name\",
   OWNER					\"Owner\",
   TABLESPACE_NAME				\"Tablespace name\",
   EXTENT_ID					\"Extent ID\",
   TO_CHAR(BYTES,'999,999,999,999')		\"Bytes\",
   BLOCK_ID					\"Block ID\",
   BLOCK_ID+BLOCKS-1				\"Blocks\"
FROM DBA_EXTENTS
   WHERE FILE_ID = $filenum
   AND $block_id BETWEEN BLOCK_ID AND BLOCK_ID+BLOCKS-1
";

      $text = "Object found with FILE# $filenum BLOCK_ID $block_id";
      $link = "";
      $infotext = "No object found with FILE# $filenum BLOCK_ID $block_id";
      DisplayTable($sql,$text,$link,$infotext);

      $sql = "
SELECT
   FILE_NAME
FROM DBA_DATA_FILES
   WHERE FILE_ID = $filenum
";

      $text = "Object exists in this datafile.";
      $link = "";
      $infotext = "";
      DisplayTable($sql,$text,$link,$infotext);
     
      Footer();

   }

# Check to see if it is a username

   $sql = "$copyright
SELECT  
   USERNAME			\"Username\"
FROM DBA_USERS 
   WHERE USERNAME = UPPER('$object_name')
";

   $text = "A username matches your search.";
   $link = "$scriptname?database=$database&schema=$object_name&object_type=USERINFO";
   $infotext = "No usernames match your search keyword";
   DisplayTable($sql,$text,$link,$infotext);

# Check to see if it is a tablespace

   $sql = "$copyright
SELECT  
   TABLESPACE_NAME		\"Tablespace name\"
FROM DBA_TABLESPACES 
   WHERE TABLESPACE_NAME = UPPER('$object_name')
";

   $text = "A tablespace name matches your search.";
   $link = "$scriptname?database=$database&schema=$object_name&object_type=TSINFO";
   $infotext = "No tablespace names match your search keyword";
   DisplayTable($sql,$text,$link,$infotext);

# Get owner if one is specified

   $_ = $object_name;
   if (/\./) {
      ($schema, $object_name) = split /\./;
      $moresql = "AND OWNER = UPPER('$schema')";
   }

   $sql = "$copyright
SELECT
   OBJECT_NAME                  \"Object name\",
   OBJECT_TYPE                  \"Object type\",
   OWNER                        \"Owner\",
   OBJECT_ID			\"Object ID\"
FROM DBA_OBJECTS
   WHERE OBJECT_NAME LIKE UPPER('\%$object_name\%')
   AND OBJECT_TYPE NOT LIKE '%PARTITION'
   $moresql
ORDER BY 1,2,3
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $object_found = $cursor->fetchrow_array;
   $cursor->finish;

   if ($object_found) {

      text("The following 'LIKE' objects were found.");

   # Print the heading

      print <<"EOF";
  <FORM METHOD=POST ACTION=$scriptname>
    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
    <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Show marked object dependencies">
    <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
    <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
    <INPUT TYPE="HIDDEN" NAME="arg" VALUE="dependencies">
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Mark</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Object name</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Object type</T
H>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Owner</TH>
EOF

      $cursor = $dbh->prepare($sql);
      $cursor->execute;

      while (($obj_name,$object_type,$owner,$object_id) = $cursor->fetchrow) {
         $_ = $object_type;
         s/ /+/g;
# Object ID's are sometimes not returned because of database link naming conventions...
         if ($object_id) {
            print <<"EOF";
        <TR>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><INPUT TYPE=CHECKBOX NAME=dependency~$object_id></TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A href=$scriptname?database=$database&arg=$obj_name&object_type=$_&schema=$owner>$obj_name</A></TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$object_type</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$owner</TD>
        </TR>
EOF
         }
      }
      $cursor->finish;
      print <<"EOF";
      </TABLE>
    </TD>
  </TR>
  </FORM>
</TABLE>
EOF
   } else {
      message("No objects \"LIKE\" $object_name were found.");
   }

# If $object_name is a number, search by object_id as well.

   $_ = $object_name;
   if ( ! /\D/ ) {

      $sql = "$copyright
SELECT
   OBJECT_NAME                  \"Object name\",
   OBJECT_TYPE                  \"Object type\",
   OWNER                        \"Owner\"
FROM DBA_OBJECTS
   WHERE OBJECT_ID = '$object_name'
";

      $text = "The following object was found with object_id $object_name";
      $link = "";
      $infotext = "No objects were found with object_id $object_name";
      ObjectTable($sql,$text,$infotext);
   }

   if ($count && ! $ENV{'LIMIT_SEARCH'}) {
      $sql = "$copyright
SELECT 
   A.USERNAME		\"User accessing\",
   A.OSUSER		\"OS Username\",
   A.PROCESS		\"Process ID\", 
   A.PROGRAM		\"Program\", 
   B.SID		\"SID\",
   A.SERIAL#		\"Serial#\",
   B.OBJECT		\"Object name\",
   B.OWNER		\"Owner\",
   B.TYPE		\"Object type\"
FROM V\$SESSION A, V\$ACCESS B
   WHERE B.OBJECT IN
(SELECT OBJECT_NAME 
   FROM DBA_OBJECTS
WHERE OBJECT_NAME LIKE UPPER('\%$object_name\%') $moresql
  AND A.SID = B.SID AND A.STATUS = 'ACTIVE')
";

      $text = "Objects currently being accessed that match your search";
      $link = "";
      $infotext = "No objects that match your search are currently being accessed";
      DisplayTable($sql,$text,$link,$infotext);

      logit("Exit subroutine objectSearch");

   }
}

sub showConstraint {

   logit("Enter subroutine showConstraint");

   my ($sql,$text,$link);

# Constraint info

   $sql = "$copyright
SELECT * FROM
   (SELECT
      TABLE_NAME				\"Table_name\",
      CONSTRAINT_NAME				\"Constraint name\"
    FROM DBA_CONSTRAINTS
       WHERE OWNER = '$schema'
       AND CONSTRAINT_NAME = '$object_name'),
   (SELECT 
       TABLE_NAME				\"Parent table\",
       CONSTRAINT_NAME				\"Parent constraint\",
       OWNER					\"Parent owner\"
    FROM DBA_CONSTRAINTS
       WHERE CONSTRAINT_NAME = 
    (SELECT R_CONSTRAINT_NAME 
        FROM DBA_CONSTRAINTS
     WHERE CONSTRAINT_NAME = '$object_name'
        AND OWNER = '$schema'))
";

   $text = "General info: Constraint $object_name";
   $link = "";
   DisplayTable($sql,$text,$link);

   logit("Exit subroutine showConstraint");

}

sub showView() {

   logit("Enter subroutine showView");

   my ($sql,$cursor,$status,$text,$infotext,$link,$foo,$object_id);

print <<"EOF";
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 cellpadding=5 cellspacing=1>
        <TR>
          <TD BGCOLOR=$headingcolor>
            <TABLE BORDER=0 CELLPADDING=0 CELLSPACING=0>
              <TR>
                <TD ALIGN=CENTER>
                  <FORM METHOD="GET" ACTION="$scriptname">
                    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
                    <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
                    <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="TABLEROWS">
                    <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
                    <INPUT TYPE="HIDDEN" NAME="arg" VALUE="$object_name">
                    <INPUT TYPE="SUBMIT" NAME="tablerows" VALUE="Display $rowdisplay rows of this view">
                </TD>
              </TR>
              <TR>
                <TD ALIGN=CENTER><FONT COLOR=$fontcolor SIZE=$fontsize><B><I>where</I></B></FONT></TD>
              </TR>
              <TR>
                <TD ALIGN=CENTER>
                    <INPUT TYPE="TEXT" SIZE=30 NAME="whereclause">
                </TD>
                  </FORM>
              </TR>
            </TABLE>
          </TD>
        </TR>
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF

showGrantButton();

#  Comments.

   $sql = "$copyright
SELECT
   COMMENTS                                      \"Comment\"
   FROM DBA_TAB_COMMENTS
WHERE (TABLE_NAME = '$object_name')
AND (OWNER = '$schema')
";

$object_type = lc $object_type;
$text = "Comment on $object_type $object_name";
$link = "";
DisplayTable($sql,$text,$link) if( recordCount($dbh,$sql) );

# General info

   $sql = "$copyright
SELECT
   TO_CHAR(CREATED,'Month DD, YYYY - HH24:MI')          \"Date created\",
   TO_CHAR(LAST_DDL_TIME,'Month DD, YYYY - HH24:MI')    \"Last compiled\",
   STATUS                                               \"Status\"
FROM DBA_OBJECTS
   WHERE OBJECT_NAME = '$object_name'
   AND OBJECT_TYPE = '$object_type'
   AND OWNER = '$schema'
";

   $text = "General info: $object_type $object_name";
   DisplayTable($sql,$text);

   checkValidity();

   $object_type = lc $object_type;

# View structure

   $sql = "$copyright
SELECT
   A.COLUMN_NAME                                  \"Column name\",
   A.DATA_TYPE                                    \"Type\",
   A.DATA_LENGTH                                  \"Length\",
   B.COMMENTS                                     \"Comments\"
FROM DBA_TAB_COLUMNS A, DBA_COL_COMMENTS B
   WHERE A.TABLE_NAME = '$object_name'
   AND A.OWNER = '$schema'
   AND A.TABLE_NAME = B.TABLE_NAME
   AND A.OWNER = B.OWNER
   AND A.COLUMN_NAME = B.COLUMN_NAME
ORDER BY A.COLUMN_ID
";

   $object_type = lc $object_type;
   $text = "Structure of $object_type $object_name";
   $link = "";
   DisplayTable($sql,$text,$link);

   $sql = "$copyright
SELECT
   SYNONYM_NAME                 \"Synonym name\",
   OWNER                        \"Owner\",
   DB_LINK                      \"DB link\"
FROM DBA_SYNONYMS
   WHERE TABLE_NAME = '$object_name'
   AND TABLE_OWNER = '$schema'
";

   $text = "Synonyms pointing to this view.";
   $link = "";
   $infotext = "There are no synonyms pointing to this view.";
   DisplayTable($sql,$text,$link,$infotext);

   $sql = "
SELECT
   OBJECT_ID 
FROM DBA_OBJECTS
   WHERE
OBJECT_NAME = '$object_name'
AND OWNER = '$schema'
AND OBJECT_TYPE = 'VIEW'
";
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $object_id = $cursor->fetchrow_array;
   $cursor->finish;

   showDependencies($object_id);

# View source

   $sql = "$copyright
SELECT 
   TEXT						\"Text\"	
FROM DBA_VIEWS 
   WHERE VIEW_NAME = '$object_name' 
   AND OWNER = '$schema'";
   $text = "Text: $object_type $object_name";
   DisplayPiecedData($sql,$text);

   logit("Exit subroutine showView");

}

sub checkValidity {

   logit("Enter subroutine checkValidity");

   my ($sql,$cursor,$status,$text);

   # Check for validity. If invalid, show additional info.

   $object_type = uc($object_type);

   $sql = "$copyright
SELECT
   STATUS
FROM DBA_OBJECTS
   WHERE OBJECT_NAME = '$object_name'
   AND OBJECT_TYPE = '$object_type'
   AND OWNER = '$schema'
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $status = $cursor->fetchrow_array;
   $cursor->finish;

   if ($status eq "INVALID" or $status eq "UNUSABLE") {

      $sql = "$copyright
SELECT
   LINE         \"Line\",
   POSITION     \"Position\",
   TEXT         \"Text\"
FROM DBA_ERRORS
   WHERE NAME = '$object_name'
   AND TYPE = '$object_type'
   AND OWNER = '$schema'
ORDER BY SEQUENCE
";
      $text = "Errors";
      DisplayTable($sql,$text);
   }

   logit("Enter subroutine checkValidity");
}

sub showTrigger {

   logit("Enter subroutine showTrigger");

   my ($sql,$text,$link);

# General info

$sql = "$copyright
SELECT 
   TRIGGER_NAME					\"Trigger name\",
   TRIGGER_TYPE					\"Trigger type\",
   TRIGGERING_EVENT				\"Triggering event\",
   REFERENCING_NAMES				\"Referencing names\",
   WHEN_CLAUSE					\"When clause\",
   STATUS					\"Status\"
FROM DBA_TRIGGERS
   WHERE TRIGGER_NAME = '$object_name'
   AND OWNER = '$schema'
";

   $text = "Trigger: $object_name";
   DisplayTable($sql,$text,$link);

   checkValidity();

# Source

$sql = "$copyright
SELECT
    TRIGGER_BODY				\"Trigger body\"
FROM DBA_TRIGGERS
   WHERE TRIGGER_NAME = '$object_name'
AND OWNER = '$schema'
";

   $text = "Trigger body";
   DisplayPiecedData($sql,$text);

   logit("Exit subroutine showTrigger");

}

sub showDBlink() {

   logit("Enter subroutine showDBlink");

   my ($sql,$text,$link);

# General info

   $sql = "$copyright
SELECT 
   DB_LINK					\"Link name\", 
   USERNAME					\"Username\", 
   HOST						\"Host\", 
   CREATED					\"Created\" 
FROM DBA_DB_LINKS 
   WHERE DB_LINK = '$object_name' 
   AND OWNER = '$schema'"
;
   $text = "Database link: $object_name";
   $link = "";
   DisplayTable($sql,$text,$link);

   logit("Exit subroutine showDBlink");

}

sub showSource() {

   logit("Enter subroutine showSource");

   my ($sql,$cursor,$status,$text,$infotext,$link);

   showGrantButton();

# General info

   $sql = "$copyright
SELECT
   TO_CHAR(CREATED,'Month DD, YYYY - HH24:MI')          \"Date created\",
   TO_CHAR(LAST_DDL_TIME,'Month DD, YYYY - HH24:MI')    \"Last compiled\",
   STATUS						\"Status\"
FROM DBA_OBJECTS
   WHERE OBJECT_NAME = '$object_name'
   AND OBJECT_TYPE = '$object_type'
   AND OWNER = '$schema'
";

   $text = "General info: $object_type $object_name";
   DisplayTable($sql,$text);

   checkValidity();

   $sql = "$copyright
SELECT
   SYNONYM_NAME                 \"Synonym name\",
   OWNER                        \"Owner\",
   DB_LINK                      \"DB link\"
FROM DBA_SYNONYMS
   WHERE TABLE_NAME = '$object_name'
   AND TABLE_OWNER = '$schema'
";

   $text = "Synonyms pointing to this object.";
   $link = "";
   $infotext = "There are no synonyms pointing to this object.";
   DisplayTable($sql,$text,$link,$infotext);

# Source of object (package, procedure, etc.)

   $sql = "$copyright
SELECT 
   TEXT
FROM 
   DBA_SOURCE 
WHERE TYPE = '$object_type' 
   AND OWNER = '$schema' 
   AND NAME = '$object_name' 
ORDER BY LINE
";
   $text = "Text: $object_type $object_name";
   $link = "";
   DisplayPiecedData($sql,$text,$link);

   logit("Exit subroutine showSource");
}

sub showSequence() {

   my ($sql,$text,$link);

   logit("Enter subroutine showSequence");

   showGrantButton();

# General info

   $sql = "$copyright
SELECT 
   MIN_VALUE					\"Min value\", 
   MAX_VALUE					\"Max value\", 
   INCREMENT_BY					\"Increment by\", 
   CYCLE_FLAG					\"Cycle flag\", 
   ORDER_FLAG					\"Order flag\", 
   CACHE_SIZE					\"Cache size\", 
   LAST_NUMBER					\"Last number\" 
FROM DBA_SEQUENCES 
   WHERE SEQUENCE_NAME = '$object_name' 
   AND SEQUENCE_OWNER = '$schema'
";
   $text = "$object_type $object_name";
   $link = "";
   DisplayTable($sql,$text,$link);

   logit("Enter subroutine showSequence");

}

sub showGrantsto() {

   my ($sql,$text,$link,$infotext);

   logit("Enter subroutine showGrantsto");

# System privileges

   $sql = "$copyright
SELECT 
   PRIVILEGE					\"Privilege\", 
   ADMIN_OPTION					\"Admin option\"
FROM DBA_SYS_PRIVS 
   WHERE GRANTEE = '$schema'
";
   $text = "System privileges granted to $schema";
   $link = "";
   $infotext = "There are no system privileges granted to $schema.";
   DisplayTable($sql,$text,$link,$infotext);

# Granted roles

   $sql = "$copyright
SELECT 
   GRANTED_ROLE					\"Granted role\", 
   ADMIN_OPTION					\"Admin option\", 
   DEFAULT_ROLE					\"Default role\" 
FROM DBA_ROLE_PRIVS 
   WHERE GRANTEE = '$schema'
";
   $text = "Roles granted to $schema";
   $link = "$scriptname?database=$database&schema=$schema&object_type=ROLES";
   $infotext = "There are no roles granted to $schema.";
   DisplayTable($sql,$text,$link,$infotext);

# Granted object privileges (explicit)

   $sql = "$copyright
SELECT 
   PRIVILEGE					\"Privilege\", 
   TABLE_NAME					\"Table name\", 
   GRANTOR					\"Grantor\", 
   GRANTABLE					\"Grantable\" 
FROM DBA_TAB_PRIVS 
   WHERE GRANTEE = '$schema' 
ORDER BY GRANTOR, TABLE_NAME
";
   $text = "Explicit grants to $schema";
   $link = "";
   $infotext = "There are no explicit grants to $schema.";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine showGrantsto");

}

sub showRoles {

   logit("Enter subroutine showRoles");

   my ($sql,$text,$link,$infotext);

   $sql = "$copyright
SELECT
   GRANTEE		\"Granted user\"
FROM DBA_ROLE_PRIVS
   WHERE GRANTED_ROLE = '$object_name'
   AND GRANTEE IN (
SELECT USERNAME 
   FROM DBA_USERS
)
";

   $text = "Users which are granted this role.";
   $link = "$scriptname?database=$database&object_type=USERINFO";
   $infotext = "No users are granted this role.";
   DisplayColTable($sql,$text,$link,$infotext,$schema_cols);

   $sql = "$copyright
SELECT
   GRANTEE		\"Granted user\"
FROM DBA_ROLE_PRIVS
   WHERE GRANTED_ROLE = '$object_name'
   AND GRANTEE IN (
SELECT ROLE 
   FROM DBA_ROLES
)
";

   $text = "Roles which are granted this role.";
   $link = "";
   $infotext = "No roles are granted this role.";
   DisplayTable($sql,$text,$link,$infotext);

# Roles granted to this role

   $sql = "$copyright
SELECT 
   GRANTED_ROLE					\"Granted role\", 
   ADMIN_OPTION					\"Admin option\", 
   DEFAULT_ROLE					\"Default role\" 
FROM DBA_ROLE_PRIVS 
   WHERE GRANTEE = '$object_name'
";
   $text = "Roles granted to role $object_name"; 
   $link = "$scriptname?database=$database&object_type=ROLES"; 
   $infotext = "There are no roles granted to this role.";
   DisplayTable($sql,$text,$link,$infotext);

# System privileges granted to this role

   $sql = "$copyright
SELECT 
   PRIVILEGE					\"Privilege\", 
   ADMIN_OPTION					\"Admin option\" 
FROM DBA_SYS_PRIVS 
   WHERE GRANTEE = '$object_name' 
ORDER BY PRIVILEGE
";
   $text = "System privileges granted to role $object_name";
   $link = "";
   $infotext = "There are no system privileges granted to this role.";
   DisplayTable($sql,$text,$link,$infotext);

# Object privileges granted to this role

   $sql = "$copyright
SELECT 
   PRIVILEGE					\"Privilege\", 
   TABLE_NAME					\"Table name\", 
   GRANTOR					\"Grantor\", 
   GRANTABLE					\"Grantable?\" 
FROM DBA_TAB_PRIVS 
   WHERE GRANTEE = '$object_name' 
ORDER BY GRANTOR, TABLE_NAME
";
   $text = "Object privileges granted to role $object_name";
   $link = "";
   $infotext = "There are no object privileges granted to this role.";
   DisplayTable($sql,$text,$link,$infotext);


   logit("Exit subroutine showRoles");

}

sub showGrantsfrom {

   logit("Enter subroutine showGrantsfrom");

   my ($sql,$text,$link,$infotext);
 
# Object privileges granted from this user

   $sql = "$copyright
SELECT 
   GRANTEE, 
   PRIVILEGE, 
   TABLE_NAME, 
   GRANTABLE 
FROM DBA_TAB_PRIVS 
   WHERE GRANTOR = '$schema' 
ORDER BY GRANTEE, TABLE_NAME
";
   $text = "Object privileges granted from user $schema";
   $link = "";
   $infotext = "$schema has not granted any privileges to other users. $schema is a stingy user.";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine showGrantsfrom");

}

sub opsMenu {

   logit("Enter subroutine opsMenu");

   my ($sql,$cursor,$text,$link,$infotext,$instance,$color);
   my ($instance_name,$instance_number,$thread,$hostname,$startup_time);
   my $highlight = "#FFFFC6";

# All instance info
# The instance name wil be a hyperlink to connect to that database.
# Instance that you are connected to will be highlighted.

   text("Active instances.");

   print <<"EOF";
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 cellpadding=2 cellspacing=1>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Instance name</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Instance number</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Thread#</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Hostname</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Startup time</TH>
EOF

   $sql = "
SELECT INSTANCE_NAME
   FROM V\$INSTANCE
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $instance = $cursor->fetchrow_array;
   $cursor->finish;

   $sql = "$copyright
SELECT INSTANCE_NAME						\"Instance name\",
   INSTANCE_NUMBER						\"Instance #\",
   THREAD#							\"Thread\",
   HOST_NAME							\"Hostname\",
   TO_CHAR(STARTUP_TIME,'Day, Month DD YYYY - HH24:MI:SS')	\"Startup time\"
FROM GV\$INSTANCE
   ORDER BY INSTANCE_NAME
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   while (($instance_name,$instance_number,$thread,$hostname,$startup_time) = $cursor->fetchrow_array) {
      if ($instance_name eq $instance) {
         $color = $highlight;
      } else {
         $color = $cellcolor;
      }
      print "        <TR ALIGN=LEFT><TD VALIGN=TOP BGCOLOR='$color'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A href=$scriptname?database=$instance_name&object_type=FRAMEPAGE TARGET=_top>$instance_name</A></TD>\n";
      print <<"EOF";
          <TD VALIGN=TOP BGCOLOR='$color'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$instance_number</A></TD>
          <TD VALIGN=TOP BGCOLOR='$color'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$thread</A></TD>
          <TD VALIGN=TOP BGCOLOR='$color'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$hostname</A></TD>
          <TD VALIGN=TOP BGCOLOR='$color'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$startup_time</A></TD></TR>
EOF
   }
   $cursor->finish;

   print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
<P>
EOF

   Button("$scriptname?database=$database&object_type=OPSINFO&command=sessions TARGET=body","Global session info","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=OPSINFO&command=sessionwait TARGET=body","Global session wait info","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=OPSINFO&command=sessionwaitbyevent TARGET=body","Global session wait info by event","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=OPSINFO&command=transactions TARGET=body","Global transaction info","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=OPSINFO&command=locks TARGET=body","Global lock info","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=OPSINFO&command=dlm TARGET=body","Lock manager info","$headingcolor","CENTER","200");

   logit("Enter subroutine opsMenu");

}

sub opsInfo {

   logit("Enter subroutine opsInfo");

   my ($sql,$cursor,$text,$link,$infotext);
   my ($instance_name,$instance_number,$thread,$hostname,$startup_time);
   my $command = $query->param('command');

# Global session wait info.

   if ($command eq "sessionwait") {

#      $sql = "$copyright
#SELECT
#   VS.INST_ID                                           \"Instance ID\",
#   VS.USERNAME                                          \"Username\",
#   VS.OSUSER                                            \"OS user\",
#   VSW.SID                                              \"SID\",
#   VSW.EVENT                                            \"Waiting on..\",
#   TO_CHAR(VSW.SECONDS_IN_WAIT,'999,999,999,999')       \"Seconds waiting\",
#   TO_CHAR(VSW.SECONDS_IN_WAIT/60,'999,999,999,999')    \"Minutes waiting\",
#   VST.SQL_TEXT                                         \"SQL text\"
#FROM GV\$SESSION_WAIT VSW,
#     GV\$SQLTEXT VST,
#     GV\$SESSION VS
#WHERE VS.INST_ID = VSW.INST_ID
#AND VS.INST_ID = VST.INST_ID
#AND VS.STATUS = 'ACTIVE'
#AND VSW.SID = VS.SID
#AND VS.USERNAME IS NOT NULL
#AND VS.SQL_ADDRESS = VST.ADDRESS
#AND VST.PIECE = 0
#ORDER BY VSW.SECONDS_IN_WAIT DESC
#";

      $sql = "$copyright
SELECT
   INST_ID                                           \"Instance ID\",
   SID                                              \"SID\",
   EVENT                                            \"Waiting on..\",
   TO_CHAR(SECONDS_IN_WAIT,'999,999,999,999')       \"Seconds waiting\",
   TO_CHAR(SECONDS_IN_WAIT/60,'999,999,999,999')    \"Minutes waiting\"
FROM GV\$SESSION_WAIT
ORDER BY SECONDS_IN_WAIT DESC
";

      $text = "Session wait information for active sessions.";
      $link = "";
      $infotext = "There are no sessions in a wait state.";
      DisplayTable($sql,$text,$link,$infotext);

   }

   if ($command eq "sessionwaitbyevent") {

      $sql = "$copyright
SELECT
   INST_ID		\"Instance\",
   EVENT                \"Waiting on\",
   MAX(SECONDS_IN_WAIT) \"Seconds waiting\"
FROM GV\$SESSION_WAIT
   GROUP BY INST_ID, EVENT
   ORDER BY 1 ASC,3 DESC
";
      $text = "Session wait information by event.";
      $link = "";
      $infotext = "There are no sessions in a wait state.";
      DisplayTable($sql,$text,$link,$infotext);
   }

   if ($command eq "locks") {

# Locked objects

      $sql = "$copyright
SELECT
   DO.OBJECT_NAME		\"Object name\",
   DO.OBJECT_TYPE		\"Object type\",
   DO.OWNER			\"Owner\",
   VLO.INST_ID			\"Instance ID\",
   VLO.SESSION_ID		\"SID\",
   VLO.ORACLE_USERNAME		\"Ora user\",
   VLO.OS_USER_NAME		\"OS user\",
   VLO.PROCESS			\"Process\",
   VLO.LOCKED_MODE		\"Mode\"
FROM GV\$LOCKED_OBJECT VLO, DBA_OBJECTS DO
   WHERE VLO.OBJECT_ID = DO.OBJECT_ID
";
      $text = "Objects which currently have locks.";
      $infotext = "There are currently no locked objects.";
      ObjectTable($sql,$text,$infotext);

   }

   if ($command eq "transactions") {

   refreshButton();

# Active transactions

      $sql = "$copyright
SELECT
   SA.INST_ID				\"Inst ID\",
   OSUSER                               \"OS user\",
   USERNAME                             \"Ora user\",
   SID                                  \"SID\",
   SERIAL#                              \"Serial#\",
   SEGMENT_NAME                         \"RBS\",
   SA.SQL_TEXT                          \"SQL Text\"
FROM   GV\$SESSION S,
       GV\$TRANSACTION T,
       DBA_ROLLBACK_SEGS R,
       GV\$SQLAREA SA
WHERE    S.TADDR = T.ADDR
AND    T.XIDUSN = R.SEGMENT_ID(+)
AND    S.SQL_ADDRESS = SA.ADDRESS(+)
";

      $text = "Global transaction info";
      $link = "";
      $infotext = "No current transactions on any segments";
      DisplayTable($sql,$text,$link,$infotext);

   }

   if ($command eq "sessions") {

      if ($oracle10) {

         $sql = "$copyright
SELECT
   INST_ID                                      \"Instance\",
   USERNAME                                 \"Ora user\",
   OSUSER                                   \"OS user\",
   SID                                      \"SID\",
   SERIAL#                                  \"Serial#\",
   STATUS                                   \"Status\",
   PROCESS                                  \"Process\",
   PROGRAM                                  \"Program\",
   TO_CHAR(LOGON_TIME,'Day MM/DD/YY HH24:MI')       \"Logon time\"
FROM GV\$SESSION 
   WHERE USERNAME IS NOT NULL
   ORDER BY INST_ID, USERNAME, STATUS
";
      } else {

# Session list

         $sql = "$copyright
SELECT
   GVS.INST_ID                                  \"Instance\",
   GVS.USERNAME                                 \"Ora user\",
   GVS.OSUSER                                   \"OS user\",
   GVS.SID                                      \"SID\",
   GVS.SERIAL#                                  \"Serial#\",
   GVS.STATUS                                   \"Status\",
   GVS.PROCESS                                  \"Process\",
   GVS.PROGRAM                                  \"Program\",
   TO_CHAR(GVS.LOGON_TIME,'Day MM/DD/YY HH24:MI')       \"Logon time\",
   GVST.SQL_TEXT                                \"SQL text\"
FROM GV\$SESSION GVS, GV\$SQLTEXT GVST
   WHERE GVS.USERNAME IS NOT NULL
   AND GVST.ADDRESS = GVS.SQL_ADDRESS
   AND GVST.INST_ID = GVS.INST_ID
   AND GVST.PIECE = 0
   ORDER BY GVS.INST_ID, GVS.USERNAME, GVS.STATUS
";

      }

      $text = "Global session summary.";
      $link = "";
      $infotext = "";
      DisplayTable($sql,$text,$link,$infotext);

   }

   if ($command eq "dlm") {

# Lock (IDLM) information

      $sql = "$copyright
SELECT
   A.INSTANCE_NAME			\"Instance Name\",
   B.FROM_VAL				\"From\",
   B.TO_VAL				\"To\",
   B.ACTION_VAL				\"Action\",
   TO_CHAR(B.COUNTER,'999,999,999,999')	\"Counter\"
FROM GV\$INSTANCE A, GV\$LOCK_ACTIVITY B
   WHERE B.INST_ID = A.INST_ID
   ORDER BY A.INSTANCE_NAME, B.COUNTER DESC
";

      $text = "Lock conversions by instance.";
      $link = "";
      $infotext = "No lock conversions";
      DisplayTable($sql,$text,$link,$infotext);

   }

   logit("Exit subroutine opsInfo");

}
   
sub showUsers {

   logit("Enter subroutine showUsers");

   my ($sql,$user,$dbid,@dbausers,@connectedusers,$dba,$connected,$text,$cursor);
   my (@lockedusers,$locked,$skip,$counter,$row,$usercount,$i,$moretext);

   my $highlight = "#FFFFC6";
   my $redlight  = "#DEBDDE";

# Show database connection info
  logit("   Showing connection information"); 

  $sql = "
SELECT
   DBID
FROM V\$DATABASE
";
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $dbid = $cursor->fetchrow_array;
   $cursor->finish;

   if ($hostname) {
      $moretext = "Hostname : $hostname";
   } else {
      $moretext = "";
   }

   if ($dbid) {
      $moretext = "$moretext (DBID : $dbid)";
   }

   print <<"EOF";
Connected to database : $database $moretext<BR>
$banner
<P>
EOF

# If database is not open, show a message explaining this.

   if ($dbstatus ne "OPEN") {
      logit("Database is not open, displaying warning message.");
      message("Warning: this database is in $dbstatus mode. Operations will be limited.");
      return;
   }

  logit("   Done showing connection information"); 

  logit("   Getting list of users with DBA role"); 

# Get all users who have the DBA role granted to them

   $sql = "$copyright
SELECT GRANTEE 
   FROM DBA_ROLE_PRIVS
WHERE GRANTED_ROLE='DBA'
";


   $cursor = $dbh->prepare($sql) or ErrorPage ("$DBI::errstr");
   $cursor->execute or ErrorPage ("$DBI::errstr");

   while ($user = $cursor->fetchrow_array) { 
      push (@dbausers,$user);
   }

   $cursor->finish;

   logit("   Done getting list of users with DBA role"); 

# Get all users whose account status is not "OPEN", if Oracle8

   if (! $oracle7) {

      logit("   We are > oracle7: Getting users with non-open accounts");

      $sql = "$copyright
SELECT USERNAME
   FROM DBA_USERS
WHERE ACCOUNT_STATUS <> 'OPEN'
";
      $cursor = $dbh->prepare($sql) or ErrorPage ("$DBI::errstr");
      $cursor->execute or ErrorPage ("$DBI::errstr");

      while ($user = $cursor->fetchrow_array) {
         push (@lockedusers,$user);
      }

      $cursor->finish;
      logit("   Done getting users with non-open accounts");
   }

# Get all users that are currently connected.

   logit("   Getting list of currently connected users");

   $sql = "$copyright
SELECT DISTINCT USERNAME
   FROM V\$SESSION
WHERE USERNAME IS NOT NULL
";

   $cursor = $dbh->prepare($sql) or ErrorPage ("$DBI::errstr");
   $cursor->execute or ErrorPage ("$DBI::errstr");

   while ($user = $cursor->fetchrow_array) {
      push (@connectedusers,$user);
   }

   $cursor->finish;

   logit("   Done getting list of currently connected users");

# Display a count of all users.

   logit("   Getting count of all users");

   $sql = "$copyright
SELECT COUNT(*)
   FROM DBA_USERS
";

   $cursor = $dbh->prepare($sql) or ErrorPage ("$DBI::errstr");
   $cursor->execute or ErrorPage ("$DBI::errstr");
   $usercount = $cursor->fetchrow_array;
   $cursor->finish;

   logit("   Done getting count of all users");

# Get all usernames

   $sql = "$copyright
SELECT 
   USERNAME 
FROM DBA_USERS 
   ORDER BY USERNAME
";
   if (! $oracle7) {
      logit("   We are > Oracle7, so check for account status");
      $text = "Select a schema by clicking on it.<BR>Yellow: User is connected. Red: Account locked / expired<BR>Bold text in parenthesis indicates DBA authority.";
   } else {
      logit("   We are < Oracle8, so don't check for account status");
      $text = "Select a schema by clicking on it.<BR>Yellow background indicates user is connected.<BR>Bold text in parenthesis indicates DBA authority.";
   }
   $cursor = $dbh->prepare($sql) or ErrorPage ("$DBI::errstr");
   $cursor->execute or ErrorPage ("$DBI::errstr");
   $counter=0;
   logit("   Generating HTML");
   print "<B>$text</B><P>\n";
   print "<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>\n";
   print "  <TR>\n";
   print "    <TD WIDTH=100%>\n";
   print "      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>\n";
   print "        <TH COLSPAN=$schema_cols BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><B>Total # users: $usercount</B></TH>\n"; 

   while ($row = $cursor->fetchrow_array) {
      undef $dba;
      foreach $user (@dbausers) {
         if ( $row eq $user ) {
            $dba = "yes";
            last;
         }
      }
      undef $connected;
      foreach $user (@connectedusers) {
         if ( $row eq $user ) {
            $connected = "yes";
            last;
         }
      }
      undef $locked;
      foreach $user (@lockedusers) {
         if ( $row eq $user ) {
            $locked = "yes";
            last;
         }
      }
      print "<TR ALIGN=CENTER>" if $counter == 0;
      if (($connected) && ($dba)) {
         print "<TD BGCOLOR=\"$highlight\"><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><STRONG><A href=$scriptname?database=$database&schema=$row&object_type=USERINFO>(${row})</A></STRONG></TD>\n";
      } elsif ($connected) {
         print "<TD BGCOLOR=\"$highlight\"><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A href=$scriptname?database=$database&schema=$row&object_type=USERINFO>$row</A></TD>\n";
      } elsif ($locked) {
         print "<TD BGCOLOR=\"$redlight\"><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A href=$scriptname?database=$database&schema=$row&object_type=USERINFO>$row</A></TD>\n";
      } elsif ($dba) {
         print "<TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><STRONG><A href=$scriptname?database=$database&schema=$row&object_type=USERINFO>(${row})</A></STRONG></TD>\n";
      } else {
         print "<TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A href=$scriptname?database=$database&schema=$row&object_type=USERINFO>$row</A></TD>\n";
      }
      $counter++;
      print "</TR>" if $counter == 0;
      $skip = "";
      if ($counter == $schema_cols) { 
         $counter = 0;
         $skip = "Y";
       }
   }
   if ((! $skip) && ($counter < $schema_cols)) {
      for ($i = $counter; $i < $schema_cols; $i++) {
         print "<TD BGCOLOR='$cellcolor'>&nbsp;</TD>\n";
      }
   }
   print "        </TR>\n";
   print "      </TABLE>\n";
   print "    </TD>\n";
   print "  </TR>\n";
   print "</TABLE>\n\n";

   $cursor->finish or ErrorPage ("$DBI::errstr");

   logit("Exit subroutine showUsers");

} 

sub showAuditTrail {

   logit("Enter subroutine showAuditTrail");

   my ($sql,$text,$link,$infotext,$command);

   $command = $query->param('command');

   logit("   Command: $command");
   logit("   Object name: $object_name");

   if ($command eq "statement") {

      $sql = "$copyright
SELECT
   OS_USERNAME						\"OS user\",
   USERNAME						\"Username\",
   USERHOST						\"Host\",
   TERMINAL						\"Terminal\",
   TO_CHAR(TIMESTAMP,'Day, Month DD YYYY - HH24:MI:SS') \"Timestamp\",
   OWNER						\"Owner\",
   OBJ_NAME						\"Object name\",
   ACTION_NAME						\"Action\",
   PRIV_USED						\"Priv used\"
FROM DBA_AUDIT_TRAIL
   WHERE PRIV_USED = '$object_name'
   ORDER BY TIMESTAMP DESC, OWNER
";

   $text = "Audit records: $object_name.";
   $link = "";
   $infotext = "No audit records for $object_name.";
   DisplayTable($sql,$text,$link,$infotext);

   }

   if ($command eq "object") {

      $sql = "$copyright
SELECT
   OS_USERNAME						\"OS user\",
   USERNAME						\"Username\",
   USERHOST						\"Host\",
   TERMINAL						\"Terminal\",
   TO_CHAR(TIMESTAMP,'Day, Month DD YYYY - HH24:MI:SS') \"Timestamp\",
   OWNER						\"Owner\",
   OBJ_NAME						\"Object name\",
   ACTION_NAME						\"Action\",
   PRIV_USED						\"Priv used\"
FROM DBA_AUDIT_TRAIL
   WHERE OBJ_NAME = '$object_name'
   ORDER BY TIMESTAMP DESC, OWNER
";

   $text = "Audit records: $object_name.";
   $link = "";
   $infotext = "No audit records for $object_name.";
   DisplayTable($sql,$text,$link,$infotext);

   }

   logit("Exit subroutine showAuditTrail");

} 

sub showAllAuditing {

   logit("Enter subroutine showAllAuditing");

   my ($sql,$text,$link,$infotext);

   refreshButton();

   $sql = "$copyright
SELECT 
   AUDIT_OPTION		\"Audit option\",
   USER_NAME		\"Username\",
   SUCCESS		\"Success\",
   FAILURE		\"Failure\"
FROM DBA_STMT_AUDIT_OPTS
   ORDER BY USER_NAME
";

   $text        = "Statements / system privileges which are being audited.";
   $link        = "$scriptname?database=$database&object_type=SHOWAUDITTRAIL&command=statement";
   $infotext    = "No SQL statement / system privileges are being audited.";

   DisplayTable($sql,$text,$link,$infotext); 

   # Oracle7 SQL

   $sql = "$copyright
SELECT
   OBJECT_NAME         \"Object name\",
   OBJECT_TYPE         \"Object type\",
   OWNER               \"Owner\",
   ALT                 \"Alter\",
   AUD                 \"Audit\",
   COM                 \"Comment\",
   DEL                 \"Delete\",
   GRA                 \"Grant\",
   IND                 \"Index\",
   INS                 \"Insert\",
   LOC                 \"Lock\",
   REN                 \"Rename\",
   SEL                 \"Select\",
   UPD                 \"Update\",
   REF                 \"References\",
   EXE			\"Execute\"
FROM DBA_OBJ_AUDIT_OPTS
WHERE ALT != '-/-'
OR AUD != '-/-'
OR COM != '-/-'
OR DEL != '-/-'
OR GRA != '-/-'
OR IND != '-/-'
OR INS != '-/-'
OR LOC != '-/-'
OR REN != '-/-'
OR SEL != '-/-'
OR UPD != '-/-'
OR REF != '-/-'
OR EXE != '-/-'
ORDER BY OWNER
";

   $sql = "$copyright
SELECT
   OBJECT_NAME         \"Object name\",
   OBJECT_TYPE         \"Object type\",
   OWNER               \"Owner\",
   ALT                 \"Alter\",
   AUD                 \"Audit\",
   COM                 \"Comment\",
   DEL                 \"Delete\",
   GRA                 \"Grant\",
   IND                 \"Index\",
   INS                 \"Insert\",
   LOC                 \"Lock\",
   REN                 \"Rename\",
   SEL                 \"Select\",
   UPD                 \"Update\",
   EXE                 \"Execute\",
   CRE                 \"Create\",
   REA                 \"Read\",
   WRI                 \"Write\"
FROM DBA_OBJ_AUDIT_OPTS
WHERE ALT != '-/-'
OR AUD != '-/-'
OR COM != '-/-'
OR DEL != '-/-'
OR GRA != '-/-'
OR IND != '-/-'
OR INS != '-/-'
OR LOC != '-/-'
OR REN != '-/-'
OR SEL != '-/-'
OR UPD != '-/-'
OR EXE != '-/-'
OR CRE != '-/-'
OR REA != '-/-'
OR WRI != '-/-'
ORDER BY OWNER
" if ($notoracle7);

   $text        = "Auditing options pertaining to individual objects.";
   $link        = "$scriptname?database=$database&object_type=SHOWAUDITTRAIL&command=object";
   $infotext    = "No schema objects are being audited.";

   DisplayTable($sql,$text,$link,$infotext); 

   $sql = "
SELECT DISTINCT 
   OBJ_NAME	\"Object name\",
   OWNER	\"Owner\",
   ACTION_NAME	\"Action name\",
   COUNT(*)	\"Count\"
FROM DBA_AUDIT_TRAIL
   GROUP BY OBJ_NAME, OWNER, ACTION_NAME
ORDER BY 4 DESC
";

   $text        = "Audit trail counts from individual objects.";
   $link        = "$scriptname?database=$database&object_type=SHOWAUDITTRAIL&command=object";

   DisplayTable($sql,$text,$link); 

   logit("Exit subroutine showAllAuditing");

}

sub Auditing {

   logit("Enter subroutine Auditing");

   my ($sql,$cursor,$value);

   $sql = "$copyright
SELECT
   VALUE FROM V\$PARAMETER
WHERE NAME = 'audit_trail'
";

   $cursor=$dbh->prepare($sql);
   $cursor->execute;
   $value = $cursor->fetchrow_array;

   if ( (uc($value) ne "FALSE") && (uc($value) ne "NONE")) {
      return(1);
   } else {
      return(0);
   }
   logit("Exit subroutine Auditing");
}


sub showSecurity {

   logit("Enter subroutine showSecurity");

   my ($sql,$cursor,$value,$text,$link,$infotext,$cols);

   if ( Auditing() ) { 

      print <<"EOF";
<TABLE BORDER=0 CELLPADDING=0 CELLSPACING=0>
  <TR>
    <TD ALIGMN=CENTER>
      <FORM METHOD="GET" ACTION="$scriptname">
        <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
        <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
        <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="AUDITING">
        <INPUT TYPE="SUBMIT" NAME="auditing" VALUE="Auditing information">
      </FORM>
    </TD>
  </TR>
</TABLE>
EOF
    } else {
      message("Database auditing is not enabled.");
   } 

   $sql = "$copyright
SELECT 
   ROLE
FROM DBA_ROLES
   ORDER BY ROLE
";

   $text        = "All roles for this database";
   $link	= "$scriptname?database=$database&object_type=ROLES";
   $infotext    = "There are no roles in this database";

   DisplayColTable($sql,$text,$link,$infotext,$schema_cols); 

   $sql = "$copyright
SELECT DISTINCT
   PROFILE
FROM DBA_PROFILES
   ORDER BY PROFILE
";

   $text        = "All profiles for this database";
   $link	= "$scriptname?database=$database&object_type=PROFILE";
   $infotext    = "There are no profiles in this database";

   DisplayColTable($sql,$text,$link,$infotext,$schema_cols); 

   $sql = "$copyright
SELECT GRANTEE
   FROM DBA_ROLE_PRIVS
WHERE GRANTED_ROLE='DBA'
   AND GRANTEE IN
(SELECT USERNAME 
   FROM DBA_USERS)
"; 

   $text        = "All users with the \"DBA\" role granted to them";
   $link	= "$scriptname?database=$database&object_type=USERINFO";
   $infotext    = "There are no users with the \"DBA\" role in this database";

   DisplayColTable($sql,$text,$link,$infotext,$schema_cols); 

   $sql = "$copyright
SELECT GRANTEE
        FROM DBA_ROLE_PRIVS
WHERE GRANTED_ROLE='DBA'
   AND GRANTEE IN
(SELECT ROLE
   FROM DBA_ROLES)
";

   $text        = "All roles with the \"DBA\" role granted to them";
   $link        = "$scriptname?database=$database&object_type=ROLES";
   $infotext    = "There are no roles with the \"DBA\" role in this database";

   DisplayColTable($sql,$text,$link,$infotext,$schema_cols);

   logit("Exit subroutine showSecurity");

}

sub showProfile {

   logit("Enter subroutine showProfile");

   my ($sql,$text,$link,$infotext);

   $sql = "$copyright
SELECT
   RESOURCE_NAME        \"Resource name\",
   LIMIT                \"Limit\"
FROM DBA_PROFILES
   WHERE PROFILE = '$object_name'
ORDER BY RESOURCE_NAME
" if ($oracle7);

   $sql = "$copyright
SELECT 
   RESOURCE_NAME	\"Resource name\",
   RESOURCE_TYPE	\"Resource type\",
   LIMIT		\"Limit\"
FROM DBA_PROFILES
   WHERE PROFILE = '$object_name'
ORDER BY RESOURCE_NAME
" if (! $oracle7);

   $text	= "Profile $object_name";
   $link	= "";
   $infotext	= "";

   DisplayTable($sql,$text,$link,$infotext); 

   logit("Exit subroutine showProfile");

}

sub userInfo {

   logit("Enter subroutine userInfo");

   # User info
   # Get the data from the database

   my ($sql,$cursor,$count,$text,$link,$infotext,$cols);
   my ($uname,$defts,$tmpts,$created,$profile,$objcount);
   my ($status);

   $schema = $object_name unless $schema;

# General user info

   $sql = "$copyright
SELECT 
   USERNAME,
   DEFAULT_TABLESPACE,
   TEMPORARY_TABLESPACE,
   TO_CHAR(CREATED,'Month DD, YYYY - HH24:MI'),
   PROFILE
FROM DBA_USERS 
   WHERE USERNAME = '$schema'
";

   if ($oracle8) {
      $sql = "$copyright
SELECT
   USERNAME,
   DEFAULT_TABLESPACE,
   TEMPORARY_TABLESPACE,
   TO_CHAR(CREATED,'Month DD, YYYY - HH24:MI'),
   PROFILE,
   ACCOUNT_STATUS
FROM DBA_USERS
   WHERE USERNAME = '$schema'
";
   }

   $status = "";
   $cursor=$dbh->prepare($sql);
   $cursor->execute;
   ($uname,$defts,$tmpts,$created,$profile,$status) = $cursor->fetchrow;
   $cursor->finish;

   if (! $oracle8) {
      print <<"EOF";
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TR>
          <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>User name</TH>
          <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Default tablespace</TH>
          <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Temp tablespace</TH>
          <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>User creation date</TH>
          <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Profile</TH>
        </TR>
        <TR>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=USERDDL&schema=$schema>$uname</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=TSINFO&schema=$schema&arg=$defts>$defts</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=TSINFO&schema=$schema&arg=$tmpts>$tmpts</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$created</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=PROFILE&arg=$profile>$profile</A></TD>
        </TR>
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF
   } else {
      print <<"EOF";
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TR>
          <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>User name</TH>
          <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Default tablespace</TH>
          <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Temp tablespace</TH>
          <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>User creation date</TH>
          <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Account status</TH>
          <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Profile</TH>
        </TR>
        <TR>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=USERDDL&schema=$schema>$uname</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=TSINFO&schema=$schema&arg=$defts>$defts</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=TSINFO&schema=$schema&arg=$tmpts>$tmpts</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$created</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$status</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=PROFILE&arg=$profile>$profile</A></TD>
        </TR>
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF
   }
    
# Tablespace quotas

   $sql = "$copyright
SELECT 
   TABLESPACE_NAME                       \"Tablespace\", 
   TO_CHAR(BYTES,'999,999,999,999')      \"Bytes used\", 
DECODE 
(
   MAX_BYTES,
      '-1','Unlimited', TO_CHAR(MAX_BYTES,'999,999,999,999')
)                                        \"Quota\"  
FROM DBA_TS_QUOTAS 
   WHERE USERNAME = '$schema'
ORDER BY TABLESPACE_NAME
";
   $text = "Tablespace quotas";
   $link = "$scriptname?database=$database&object_type=TSINFO&schema=$schema";
   $infotext = "$schema has no individual tablespace quotas.";

   DisplayTable($sql,$text,$link,$infotext);

# Buttons for displaying grants / session info

print <<"EOF";
<P>
<TABLE BORDER=0>
  <TR ALIGN=CENTER>
    <TD>
      <FORM METHOD="GET" ACTION="$scriptname">
        <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
        <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
        <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
        <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="GRANTSTO">
        <INPUT TYPE="SUBMIT" NAME="togrants" VALUE="Display grants to $schema">
      </FORM>
    </TD>
    <TD>
      <FORM METHOD="GET" ACTION="$scriptname">
        <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
        <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
        <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
        <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="GRANTSFROM">
        <INPUT TYPE="SUBMIT" NAME="fromgrants" VALUE="Display grants from $schema">
      </FORM>
    </TD>
  </TR>
EOF

# Display a button if the user currently has sessions in this instance.

   $sql = "$copyright
SELECT COUNT(*) 
   FROM V\$SESSION 
WHERE USERNAME = '$schema'
";
   $cursor=$dbh->prepare($sql);
   $cursor->execute;
   $count = $cursor->fetchrow_array;
   $cursor->finish;

   if ($count > 0) {
print <<"EOF";
  <TR>
    <TD COLSPAN=2 ALIGN=CENTER>
      <FORM METHOD="GET" ACTION="$scriptname">
        <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
        <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
        <INPUT TYPE="HIDDEN" NAME="username" VALUE="$schema">
        <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="TOPSESSIONS">
        <INPUT TYPE="SUBMIT" NAME="sessions" VALUE="Display $schema session info">
      </FORM>
    </TD>
  </TR>
</TABLE>
EOF
   } else {
print <<"EOF";
</TABLE>
EOF
   message("$schema has no sessions in this instance.");
   }

# Check to see if there are any public synonyms pointing
# to objects owned by the schema selected.

   $sql = "$copyright
SELECT 
   COUNT(*) 
FROM DBA_SYNONYMS
   WHERE TABLE_OWNER = '$schema'
   AND OWNER = 'PUBLIC'
";
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $objcount = $cursor->fetchrow_array || "";
   $cursor->finish;

# Get object types owned by user

   if ($objcount) {

      $sql = "$copyright
SELECT DISTINCT 
   OBJECT_TYPE				\"Object type\" 
FROM DBA_OBJECTS 
   WHERE OWNER = '$schema'
   AND OBJECT_TYPE != 'UNDEFINED'
UNION
   SELECT
DECODE(DUMMY,'X','PUBLIC SYNONYMS')
   FROM DUAL
";
      $text = "Object types owned by $schema, + public synonyms.<BR>Click an object type for a list.";

   } else {
    
      $sql = "$copyright
SELECT DISTINCT
   OBJECT_TYPE                          \"Object type\"
FROM DBA_OBJECTS
   WHERE OWNER = '$schema'
   AND OBJECT_TYPE != 'UNDEFINED'
";
      $text = "Object types owned by $schema.<BR>Click an object type for a list.";

   }

   $link = "$scriptname?database=$database&schema=$schema&object_type=LISTOBJECTS";
   $infotext = "There are no objects owned by $schema in this database.";
   DisplayColTable($sql,$text,$link,$infotext,$schema_cols);

   $sql = "$copyright
SELECT COUNT(*) FROM DBA_OBJECTS WHERE OWNER = '$schema'
";
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $objcount = $cursor->fetchrow_array;
   $cursor->finish;

   if ($objcount) {

      $sql = "$copyright
SELECT
   COUNT(DECODE(TYPE, 2, OBJ#, '')) \"Table\",
   COUNT(DECODE(TYPE, 1, OBJ#, '')) \"Index\",
   COUNT(DECODE(TYPE, 5, OBJ#, '')) \"Synonym\",
   COUNT(DECODE(TYPE, 4, OBJ#, '')) \"View`\",
   COUNT(DECODE(TYPE, 6, OBJ#, '')) \"Sequence\",
   COUNT(DECODE(TYPE, 7, OBJ#, '')) \"Procedure\",
   COUNT(DECODE(TYPE, 8, OBJ#, '')) \"Function\",
   COUNT(DECODE(TYPE, 9, OBJ#, '')) \"Package\",
   COUNT(DECODE(TYPE,12, OBJ#, '')) \"Trigger\"
FROM SYS.OBJ\$
   WHERE OWNER# = 
(
SELECT USER_ID 
   FROM DBA_USERS 
WHERE USERNAME = '$schema'
)
" if $oracle7;

      $sql = "$copyright
SELECT
   COUNT(DECODE(TYPE#, 2, OBJ#, '')) \"Table\",
   COUNT(DECODE(TYPE#, 1, OBJ#, '')) \"Index\",
   COUNT(DECODE(TYPE#, 5, OBJ#, '')) \"Synonym\",
   COUNT(DECODE(TYPE#, 4, OBJ#, '')) \"View\",
   COUNT(DECODE(TYPE#, 6, OBJ#, '')) \"Sequence\",
   COUNT(DECODE(TYPE#, 7, OBJ#, '')) \"Procedure\",
   COUNT(DECODE(TYPE#, 8, OBJ#, '')) \"Function\",
   COUNT(DECODE(TYPE#, 9, OBJ#, '')) \"Package\",
   COUNT(DECODE(TYPE#,12, OBJ#, '')) \"Trigger\"
FROM SYS.OBJ\$
   WHERE OWNER# = 
(
SELECT USER_ID 
   FROM DBA_USERS 
WHERE USERNAME = '$schema'
)
" if $notoracle7;

      $text = "Object count";
      $link = "";

      DisplayTable($sql,$text,$link);

   }

   $sql = "$copyright
SELECT 
   COUNT(*)
FROM DBA_OBJECTS
   WHERE OWNER = '$schema'
AND OBJECT_TYPE IN ('TABLE','INDEX','CLUSTER')
";

   $cursor=$dbh->prepare($sql);
   $cursor->execute;
   $count = $cursor->fetchrow_array;

   if ($count > 0) {

      print <<"EOF";
<BR>
</FONT>
<FORM METHOD="GET" ACTION="$scriptname">
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="OBJECTREPORT">
  <INPUT TYPE="SUBMIT" NAME="objectreport" VALUE="Object report by tablespace.">
</FORM>
EOF
   }

   if ($objcount) {

      $sql = "$copyright
SELECT COUNT(*)
   FROM DBA_OBJECTS
WHERE OWNER = '$schema'
AND STATUS IN ('INVALID','UNUSABLE')
";
      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      $count = $cursor->fetchrow_array;
      $cursor->finish;
      if ($count > 0) {
         if (checkPriv("ALTER ANY PROCEDURE")) {
            print <<"EOF";
</FONT>
<FORM METHOD="GET" ACTION="$scriptname">
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="SHOWINVALIDOBJECTS">
  <INPUT TYPE="SUBMIT" NAME="objectreport" VALUE="Display $count invalid objects.">
</FORM>
EOF
         } else {
            message("There are $count invalid objects in this schema.\n");
         }
      } else {
         message("There are no invalid objects in this schema.\n");
      }
   }

   logit("Exit subroutine userInfo");

}

sub showInvalidObjects {

   invalidObjectList($schema);

}

sub enterExtentReport {

   logit("Enter subroutine enterExtentReport");

   text("Enter a value below. A report will be generated showing all objects with a number of extents greater than or equal to the number you have entered. (Objects with unusually large number of extents)");

   print <<"EOF";
      <FORM METHOD="GET" ACTION="$scriptname">
        <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
        <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
        <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="EXTENTREPORT">
        <INPUT TYPE=TEXT MAXLENGTH=10 SIZE=10 NAME=extents1 VALUE=1000>
EOF
   text("Enter a value below. A report will be generated showing all objects with a number of extents greater than MAX_EXTENTS minus this number. (Objects nearing max extents)");
   print "     <INPUT TYPE=TEXT MAXLENGTH=10 SIZE=10 NAME=extents2 VALUE=25><P>\n";

   print <<"EOF";
        <INPUT TYPE="SUBMIT" NAME="foo" VALUE="Generate report">
      </FORM>
EOF

   logit("Exit subroutine enterExtentReport");

}

sub extentReport {

   logit("Enter subroutine extentReport");

   my ($sql,$cursor,$tablespace_name,$link,$text,$infotext,$extents1,$extents2);
   my (@tablespaces);

   $extents1 = $query->param('extents1');
   $extents2 = $query->param('extents2');

   logit("   Looking for objects with extents > $extents1");

   $sql = "$copyright
SELECT
   SEGMENT_NAME                                 \"Object name\",
   SEGMENT_TYPE                                 \"Object type\",
   OWNER                                        \"Owner\",
   TO_CHAR(COUNT(*),'999,999,999,999')		\"Extents\",
   TO_CHAR(SUM(BYTES),'999,999,999,999')	\"Bytes\",
   TABLESPACE_NAME                              \"Tablespace name\"
FROM DBA_EXTENTS
   GROUP BY SEGMENT_TYPE, SEGMENT_NAME, TABLESPACE_NAME, OWNER
   HAVING COUNT(*) >= $extents1 
   ORDER BY 4 DESC
";

   $text = "Objects with a number of extents >= $extents1.";
   $infotext = "There are no objects with extents >= $extents1.";

   ObjectTable($sql,$text,$infotext);
   logit("   SQL = \n$sql");
   logit("   Error: $DBI::errstr") if $DBI::errstr;

   print "<HR WIDTH='75%'>\n";

      $sql = "$copyright
SELECT
   SEGMENT_NAME                                 \"Object name\",
   SEGMENT_TYPE                                 \"Object type\",
   OWNER                                        \"Owner\",
   TABLESPACE_NAME                              \"Tablespace name\",
   TO_CHAR(EXTENTS,'999,999,999,999')           \"Extents\",
   TO_CHAR(MAX_EXTENTS,'999,999,999,999')       \"Max extents\"
FROM DBA_SEGMENTS
   WHERE EXTENTS > (MAX_EXTENTS-$extents2)
   AND SEGMENT_TYPE != 'CACHE'
";

   $text = "Objects that are approaching their max_extents limit.";
   $infotext = "No objects in the database have extents > ( max_extents - $extents2 ).";
   ObjectTable($sql,$text,$infotext);

   print "<HR WIDTH='75%'>\n";

   text("Checking all tablespaces for objects which cannot allocate a next extent due to lack of space.");

   $sql = "$copyright
SELECT 
   TABLESPACE_NAME 
FROM DBA_TABLESPACES
   ORDER BY TABLESPACE_NAME
";
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   while ($tablespace_name = $cursor->fetchrow_array) {
      push @tablespaces, $tablespace_name;
   }
   $cursor->finish;

   foreach $tablespace_name(@tablespaces) {
      $sql = "$copyright
SELECT
   SEGMENT_NAME                                 \"Object name\",
   SEGMENT_TYPE                                 \"Object type\",
   OWNER                                        \"Owner\",
   TO_CHAR(NEXT_EXTENT,'999,999,999,999')       \"Next extent\"
FROM DBA_SEGMENTS
   WHERE TABLESPACE_NAME = '$tablespace_name'
   AND NEXT_EXTENT > (SELECT NVL(MAX(BYTES),'0') FROM DBA_FREE_SPACE
WHERE TABLESPACE_NAME = '$tablespace_name')
";

      $text = "Objects in tablespace $tablespace_name which cannot allocate a next extent.";
      $link = "";
      $infotext = "Tablespace $tablespace_name OK.";
      ObjectTable($sql,$text,$infotext);
   }
   text("Done.");

   logit("Exit subroutine extentReport");

}

sub userSpaceReport {

   logit("Enter subroutine userSpaceReport");

   my ($sql,$link,$text,$sortfield,$owner,$bytes,$highlight,$color,$count);

   $sortfield = $query->param('sortfield') || "3";
   $highlight = "#FFFFC6";

   text("Click on a column name to change sort order.");

   print << "EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
EOF
   if ($sortfield eq "1") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=1>Owner</A></TH>\n";
   if ($sortfield eq "2") {
      $sortfield = "2 DESC";
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=2>Object count</A></TH>\n";
   if ($sortfield eq "3") {
      $sortfield = "3 DESC";
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=3>Bytes</A></TH>\n";

   $sql = "$copyright
SELECT
   OWNER,
   TO_CHAR(COUNT(*),'999,999,999,999'),
   TO_CHAR(SUM(BYTES),'999,999,999,999')
FROM DBA_SEGMENTS
   GROUP BY OWNER
   ORDER by $sortfield
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   while (($owner,$count,$bytes) = $cursor->fetchrow_array) {
      print "<TR><TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=OBJECTREPORT&arg=$owner>$owner</A></TD>\n";
      print "<TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$count</TD>\n";
      print "<TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$bytes</TD></TR>\n";
   }
   $cursor->finish;
   print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF

   logit("Exit subroutine userSpaceReport");

}

sub fileFragReport {

   logit("Enter subroutine fileFragReport");

   my ($sql,$link,$text,$sortfield,$file_name,$bytes,$largest,$smallest,$frags);
   my ($highlight,$color,$count,$tablespace_name,@needs_coalescing);

   my $maxfrags = 1000;

   $sortfield = $query->param('sortfield') || "4";
   $highlight = "#FFFFC6";

   text("Click on a column name to change sort order.");

   print << "EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
EOF
   if ($sortfield eq "1") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=1>File name</A></TH>\n";
   if ($sortfield eq "2") {
      $sortfield = "2 DESC";
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=2>Bytes</A></TH>\n";
   if ($sortfield eq "3") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=3>Tablespace name</A></TH>\n";
   if ($sortfield eq "4") {
      $sortfield = "4 DESC";
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=4>Fragments</A></TH>\n";
   if ($sortfield eq "5") {
      $sortfield = "5 DESC";
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=5>Largest free chunk</A></TH>\n";
   if ($sortfield eq "6") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=6>Smallest free chunk</A></TH>\n";
$sql = "$copyright
SELECT 
   A.FILE_NAME						\"File name\",
   TO_CHAR(A.BYTES,'999,999,999,999')			\"Bytes\",
   A.TABLESPACE_NAME					\"Tablespace name\",
   COUNT(*)						\"Pieces\",
   TO_CHAR(NVL(MAX(B.BYTES),'0'),'999,999,999,999')	\"Largest free chunk\", 
   TO_CHAR(NVL(MIN(B.BYTES),'0'),'999,999,999,999')	\"Smallest free chunk\"
FROM DBA_DATA_FILES A, DBA_FREE_SPACE B
WHERE A.FILE_ID = B.FILE_ID(+)
GROUP BY A.FILE_NAME, A.BYTES, A.TABLESPACE_NAME
ORDER BY $sortfield
";

   logit("   SQL = $sql");
   $cursor = $dbh->prepare($sql);
   logit("   Error: $DBI::errstr") if $DBI::errstr;
   $cursor->execute;
   while (($file_name,$bytes,$tablespace_name,$frags,$largest,$smallest) = $cursor->fetchrow_array) {
# Push tablespace_name into an array if the tablespace needs coalescing.
      if ($frags >= $maxfrags) {
         push @needs_coalescing, "'$file_name'";
         logit("   File $file_name needs coalescing.");
      }
      print "<TR><TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=DATAFILE&arg=$file_name>$file_name</A></TD>\n";
      print "<TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$bytes</TD>\n";
      print "<TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=TSINFO&arg=$tablespace_name>$tablespace_name</A></TD>\n";
      print "<TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$frags</TD>\n";
      print "<TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$largest</TD>\n";
      print "<TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$smallest</TD></TR>\n";
   }
   $cursor->finish;
   print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF

   # Print a list of "ALTER TABLESAPCE tablespace name COALESCE statements

   if (@needs_coalescing) {
      my $file_names = join(",",@needs_coalescing);
      logit("   Files to be coalesced: $file_names");
      text("Coalesce statements for tablespaces containing datafiles which have at least $maxfrags fragments.");
      print <<"EOF";
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TR>
          <TD BGCOLOR='$cellcolor'>
            <PRE>
/* 
   Database $database

   DDL generated by Oracletool v$VERSION
   for any tablespace containing at least
   one datafile with more than $maxfrags 
   fragments.
*/

EOF
       $sql = "$copyright
SELECT DISTINCT TABLESPACE_NAME
   FROM DBA_DATA_FILES
WHERE FILE_NAME IN ($file_names)
";
      $cursor = $dbh->prepare($sql) or print("$DBI::errstr\n");
      $cursor->execute;
      while ($tablespace_name = $cursor->fetchrow_array) {
         logit("   Writing statement for tablespace $tablespace_name");
         print "ALTER TABLESPACE $tablespace_name COALESCE;\n"
      }
      $cursor->finish;
      print <<"EOF";
          </TD>
        </TR>
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF
   }

   logit("Exit subroutine fileFragReport");

}


sub tsSpaceReport {

   logit("Enter subroutine tsSpaceReport");

   my ($sql,$link,$text,$sortfield,$owner,$tablespace_name,$bytes);
   my ($highlight,$color,$count);

   $sortfield = $query->param('sortfield') || "4";
   $highlight = "#FFFFC6";

   text("Click on a column name to change sort order.");

   print << "EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
EOF
   if ($sortfield eq "1") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=1>Owner</A></TH>\n";
   if ($sortfield eq "2") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=2>Tablespace name</A></TH>\n";
   if ($sortfield eq "3") {
      $sortfield = "3 DESC";
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=3>Object count</A></TH>\n";
   if ($sortfield eq "4") {
      $sortfield = "4 DESC";
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=4>Bytes used</A></TH>\n";

   $sql = "$copyright
SELECT
   OWNER,
   TABLESPACE_NAME,
   TO_CHAR(COUNT(*),'999,999,999,999'),
   TO_CHAR(SUM(BYTES),'999,999,999,999')
FROM DBA_SEGMENTS
   GROUP BY OWNER, TABLESPACE_NAME
   ORDER BY $sortfield
";

   logit("   SQL = $sql");
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   while (($owner,$tablespace_name,$count,$bytes) = $cursor->fetchrow_array) {
      print "<TR><TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=OBJECTREPORT&arg=$owner>$owner</A></TD>\n";
      print "<TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=TSINFO&arg=$tablespace_name>$tablespace_name</TD></A>\n";
      print "<TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$count</TD>\n";
      print "<TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$bytes</TD></TR>\n";
   }
   $cursor->finish;
   print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF

   logit("Exit subroutine tsSpaceReport");
   
}

sub objectReport {

   logit("Enter subroutine objectReport");

   my ($sql1,$sql2,$count,$counter,$cursor1,$cursor2);
   my ($tablespace_name,$object_type,@tablespaces,$text,$link);
   my ($segment_name,$segment_type,$created,$last_ddl_time,$bytes,$extents);

# Show all objects for a particular user ordered by tablespace.
# This can be helpful for examining which tablespaces are expected
# to exist should you need to import this user's schema into a
# different database.

   $schema = $object_name unless ($schema);

   text("Object report for schema $schema ordered by tablespace.");

  $sql1 = "$copyright
SELECT DISTINCT 
   TABLESPACE_NAME 
FROM DBA_SEGMENTS
   WHERE OWNER = '$schema'
   AND SEGMENT_TYPE NOT IN ('CACHE',
			    'ROLLBACK',
			    'TEMPORARY')
ORDER BY TABLESPACE_NAME
";

   $count=0;
   $cursor1 = $dbh->prepare($sql1); 
   $cursor1->execute;
   while ( $tablespace_name = $cursor1->fetchrow_array ) { 
      push @tablespaces, $tablespace_name;
      $count++;
   }
   $cursor1->finish;

# Exit if user has no objects anywhere.
   
   if ($count == 0) {
      print "<BR>$schema has no objects in this database.<BR>\n";
      Footer();
      exit;
   } else {
      print "<BR>Objects of type CACHE or TEMPORARY not shown.<BR>\n";
      print "$schema has objects in $count tablespace(s).<P></CENTER>\n";
      print "<B>Summary report:</B><P><CENTER>\n";
   }

# Print a summary report with object types and counts for each tablespace.

print "<TABLE>\n";

   foreach $tablespace_name (@tablespaces) {
      print "  <TR VALIGN=TOP>\n" if $counter == 0;
      print <<"EOF";
    <TD>
      <TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
        <TR>
          <TD WIDTH=100%>
            <TABLE BORDER=0 cellpadding=2 cellspacing=1>
              <TR>
                <TD COLSPAN=2 ALIGN=CENTER BGCOLOR='$headingcolor'>
                <FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$font'>$tablespace_name
                </TD>
              </TR>
              <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Object type</TH>
              <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Count</TH>
EOF

      $sql1 = "$copyright
SELECT DISTINCT SEGMENT_TYPE 
   FROM DBA_SEGMENTS
WHERE OWNER = '$schema'
AND TABLESPACE_NAME = '$tablespace_name'
AND SEGMENT_TYPE NOT IN ('CACHE',
			 'ROLLBACK',
			 'TEMPORARY')
";

      $cursor1=$dbh->prepare($sql1);
      $cursor1->execute;
      while ($object_type = $cursor1->fetchrow_array) {
         print "              <TR>\n";
         print "                <TD BGCOLOR='$cellcolor'>\n";
         print "                  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$object_type\n";
         print "                </TD>\n";
         $sql2 = "$copyright
SELECT COUNT(*) 
   FROM DBA_SEGMENTS 
WHERE OWNER = '$schema'
AND SEGMENT_TYPE = '$object_type'
AND TABLESPACE_NAME = '$tablespace_name'
";
         $cursor2=$dbh->prepare($sql2);
         $cursor2->execute;
         $count = $cursor2->fetchrow_array;
         $cursor2->finish;
         print "                <TD BGCOLOR='$cellcolor'>\n";
         print "                  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$count\n";
         print "                </TD>\n";
         print "              </TR>\n";
      }
      $cursor1->finish;
      print "            </TABLE>\n";
      $counter++;
      print "          </TD>\n";
      print "        </TR>\n";
      print "      </TABLE>\n";
      print "    </TR>\n" if $counter == 0;
      if ( $counter == 6 ) { $counter = 0 };
   }
   print "  </TR>\n";
   print "</TABLE>\n";

      print "</CENTER><P><HR WIDTH=100%><P><B>Detailed report:</B><P>\n";
      foreach $tablespace_name (@tablespaces) {
   
      $sql2 = "$copyright
SELECT
   A.SEGMENT_NAME                                       \"Object name\",
   A.SEGMENT_TYPE                                       \"Object type\",
   TO_CHAR(B.CREATED,'Month DD, YYYY - HH24:MI')          \"Created\",
   TO_CHAR(B.LAST_DDL_TIME,'Month DD, YYYY - HH24:MI')    \"Last DDL time\",
   TO_CHAR(A.BYTES,'999,999,999,999')                   \"Bytes\",
   TO_CHAR(A.EXTENTS,'999,999,999,999')                 \"Extents\"
FROM DBA_SEGMENTS A, DBA_OBJECTS B
   WHERE A.TABLESPACE_NAME = '$tablespace_name'
   AND A.OWNER = '$schema'
   AND B.OWNER = '$schema'
   AND A.SEGMENT_NAME = B.OBJECT_NAME
ORDER BY A.SEGMENT_TYPE, A.SEGMENT_NAME
";

      $text = "Tablespace $tablespace_name";
      $link = "";
      DisplayTable($sql2,$text,$link);
   }

# Show text based report

   print "<P>\n";

   format STDOUT = 
@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<< @>>>>>>>>>>>>>>>>>>> @>>>>>>>>>>>>>>
$segment_name,$segment_type,$created,$bytes,$extents
.

   print <<"EOF";
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TR>
          <TD BGCOLOR='$cellcolor'>
            <PRE>
EOF
   print "Object usage for user $schema database $database\n\n";
   foreach $tablespace_name (@tablespaces) {

      print "Tablespace $tablespace_name\n";
      print "===========================\n\n";
      print "Object name                          Object type    Date created                       # Bytes       # Extents\n";
      print "===========                          ===========    ============                       =======       =========\n";

      $sql = "$copyright
SELECT
   A.SEGMENT_NAME                                       \"Object name\",
   A.SEGMENT_TYPE                                       \"Object type\",
   TO_CHAR(B.CREATED,'Mon DD, YYYY - HH24:MI')          \"Created\",
   TO_CHAR(B.LAST_DDL_TIME,'Mon DD, YYYY - HH24:MI')    \"Last DDL time\",
   TO_CHAR(A.BYTES,'999,999,999,999')                   \"Bytes\",
   TO_CHAR(A.EXTENTS,'999,999,999,999')                 \"Extents\"
FROM DBA_SEGMENTS A, DBA_OBJECTS B
   WHERE A.TABLESPACE_NAME = '$tablespace_name'
   AND A.OWNER = '$schema'
   AND B.OWNER = '$schema'
   AND A.SEGMENT_NAME = B.OBJECT_NAME
ORDER BY A.SEGMENT_TYPE, A.SEGMENT_NAME
";
      $cursor = $dbh->prepare($sql) or print "$DBI::errstr\n";
      $cursor->execute;
      while (($segment_name,$segment_type,$created,$last_ddl_time,$bytes,$extents) = $cursor->fetchrow_array) {
         $segment_name	=~ s/ //g;
         $segment_type	=~ s/ //g;
         $bytes		=~ s/ //g;
         $extents	=~ s/ //g;
#         print "$segment_name,$segment_type,$created,$last_ddl_time,$bytes,$extents\n";
         write;
      }
      $cursor->finish;
      print "\n";
   }
   print<<"EOF";
            </PRE>
          </TD>
        </TR>
      </TABLE>
    </TD>
  </TR>
</TABLE> 
EOF
      

   logit("Exit subroutine objectReport");

}

sub showObjects {

   logit("Enter subroutine showObjects");

   my ($sql,$text,$link,$infotext,$nulltext,$count,$table_name);
   my ($cursor);

   logit("   Object is a $object_name");

# Object types with spaces are not +'d at this point.
   $object_type = $object_name;

   if ($object_type eq "SYNONYM") {

      $sql = "$copyright
SELECT
   SYNONYM_NAME		\"Synonym name\",
   TABLE_OWNER		\"Object owner\",
   TABLE_NAME		\"Object name\"
FROM DBA_SYNONYMS
   WHERE OWNER = '$schema'
";

      $infotext = "No synonyms.";
      $text = "Synonyms";
      $link = "$scriptname?database=$database&schema=$schema&object_type=$object_type";
      DisplayTable($sql,$text,$link,$infotext);

      Footer();
   }
   
# Check for the different types of tables.
# If Oracle8, the table name will not show up in DBA_SEGMENTS if
# the table is partitioned, so we will select from DBA_PART_TABLES.

   if ($object_type eq "TABLE") {

      if (! $oracle7) {
         $sql = "$copyright
SELECT
   TABLE_NAME                           \"Table name\",
   DEF_TABLESPACE_NAME                  \"Def. tablespace name\",
   PARTITIONING_TYPE                    \"Partitioning type\",
   PARTITION_COUNT                      \"Partition count\"
FROM DBA_PART_TABLES
   WHERE OWNER = '$schema'
";

         $infotext = "No partitioned tables in this schema.";
         $text = "Partitioned tables.";
         $link = "$scriptname?database=$database&schema=$schema&object_type=$object_type";
         DisplayTable($sql,$text,$link,$infotext);

# Check for Index Organized Tables, because they won't show up in DBA_SEGMENTS

         $sql = "$copyright
SELECT
   TABLE_NAME		\"Table name\"
FROM DBA_TABLES
   WHERE OWNER = '$schema'
AND IOT_TYPE = 'IOT'
";
         $infotext = "No Index Organized Tables in this schema.";
         $text = "Index Organized Tables.";
         $link = "$scriptname?database=$database&schema=$schema&object_type=$object_name";
         DisplayTable($sql,$text,$link,$infotext);
      }

      if ($oraclei) {

# Check for global temporary tables if Oracle I

         $sql = "$copyright
SELECT
   TABLE_NAME		\"Table name\"
FROM DBA_TABLES
   WHERE OWNER = '$schema'
AND TEMPORARY = 'Y'
";
         $infotext = "No global temporary tables in this schema.";
         $text = "Global temporary tables.";
         $link = "$scriptname?database=$database&schema=$schema&object_type=$object_name";
         DisplayTable($sql,$text,$link,$infotext);

      }

# Now, show the normal tables.

      logit("   Start standard tables");

      $sql = "$copyright
SELECT
   SEGMENT_NAME                         \"Object name\",
   TABLESPACE_NAME                      \"Tablespace name\",
   TO_CHAR(BYTES,'999,999,999,999')     \"Bytes\"
FROM DBA_SEGMENTS
   WHERE OWNER = '$schema'
   AND SEGMENT_TYPE = '$object_type'
ORDER BY SEGMENT_NAME
";

      $text = "Standard tables.";
      $infotext = "No standard tables in this schema.";
      $link = "$scriptname?database=$database&schema=$schema&object_type=$object_name";
      DisplayTable($sql,$text,$link,$infotext);

      exit;
   }

# If object is an index, show the space used

   if ($object_type eq "INDEX") {

      if (! $oracle7) {

# Show partitioned indexes.

         $sql = "$copyright
SELECT
   INDEX_NAME                           \"Index name\",
   DEF_TABLESPACE_NAME                  \"Def. tablespace name\",
   PARTITIONING_TYPE                    \"Partitioning type\",
   PARTITION_COUNT                      \"Partition count\"
FROM DBA_PART_INDEXES
   WHERE OWNER = '$schema'
";

         $infotext = "No partitioned indexes in this schema.";
         $text = "Partitioned indexes.";
         $link = "$scriptname?database=$database&schema=$schema&object_type=$object_type";
         DisplayTable($sql,$text,$link,$infotext);

# Show bitmapped indexes

         $sql = "$copyright
SELECT
   INDEX_NAME				\"Index name\",
   TABLESPACE_NAME			\"Tablespace name\"
FROM DBA_INDEXES
   WHERE OWNER = '$schema'
   AND INDEX_TYPE = 'BITMAP'
ORDER BY INDEX_NAME
";
         $text = "Bitmapped indexes.";
         $infotext = "No bitmapped indexes in this schema.";
         $link = "$scriptname?database=$database&schema=$schema&object_type=$object_type";
         DisplayTable($sql,$text,$link,$infotext);

# Show IOT indexes

         $sql = "$copyright
SELECT
   INDEX_NAME				\"Index name\",
   TABLESPACE_NAME			\"Tablespace name\"
FROM DBA_INDEXES
   WHERE OWNER = '$schema'
   AND INDEX_TYPE LIKE '\%IOT\%'
ORDER BY INDEX_NAME
";
         $text = "Index Organized Table indexes.";
         $infotext = "No Index Organized Table indexes in this schema.";
         $link = "$scriptname?database=$database&schema=$schema&object_type=$object_type";
         DisplayTable($sql,$text,$link,$infotext);

# Show standard indexes

         $sql = "$copyright
SELECT
   INDEX_NAME				\"Object name\",
   TABLESPACE_NAME			\"Tablespace name\"
FROM DBA_INDEXES
   WHERE OWNER = '$schema'
   AND INDEX_TYPE = 'NORMAL'
   AND PARTITIONED = 'NO'
";
         $text = "Standard indexes.";
         $infotext = "No standard indexes in this schema.";
         $link = "$scriptname?database=$database&schema=$schema&object_type=$object_type";
         DisplayTable($sql,$text,$link,$infotext);

         exit;

      } else {
       
# We are Oracle7

         $sql = "$copyright
SELECT
   INDEX_NAME				\"Object name\",
   TABLESPACE_NAME			\"Tablespace name\"
FROM DBA_INDEXES
   WHERE OWNER = '$schema'
";
         $text = "Select an index for more info.";
         $infotext = "No standard indexes in this schema.";
         $link = "$scriptname?database=$database&schema=$schema&object_type=$object_type";
         DisplayTable($sql,$text,$link,$infotext);

         exit;

      }
   }

# If object is of type partitioned, then
# show the subobject as well.

   if ($object_type eq "TABLE PARTITION") {

      $sql = "$copyright
SELECT
   TABLE_NAME                                   \"Table name\",
   PARTITION_NAME                               \"Partition name\",
   TABLE_OWNER                                  \"Owner\",
   TABLESPACE_NAME                              \"Tablespace\",
   PARTITION_POSITION                           \"Position\",
   TO_CHAR(INITIAL_EXTENT,'999,999,999,999')    \"Initial\",
   TO_CHAR(NEXT_EXTENT,'999,999,999,999')       \"Next\",
   TO_CHAR(MAX_EXTENT,'999,999,999,999')        \"Max extents\",
   PCT_INCREASE                                 \"Pct increase\",
   HIGH_VALUE                                   \"High value\",
   HIGH_VALUE_LENGTH                            \"High value length\",
   LOGGING                                      \"Logging\"
FROM DBA_TAB_PARTITIONS
   WHERE TABLE_OWNER = '$schema'
ORDER BY TABLE_NAME, PARTITION_POSITION
";

      $text = "Select a partition for info about the parent table.";
      $link = "$scriptname?database=$database&schema=$schema&object_type=TABLE";
      DisplayTable($sql,$text,$link,$infotext);
      logit("   Link = $link");

      exit;

   }

   if ($object_type eq "INDEX PARTITION") {

      $sql = "$copyright
SELECT
   INDEX_NAME					\"Index name\",
   PARTITION_NAME                               \"Partition name\",
   TABLESPACE_NAME                              \"Tablespace\",
   PARTITION_POSITION                           \"Position\",
   TO_CHAR(INITIAL_EXTENT,'999,999,999,999')    \"Initial\",
   TO_CHAR(NEXT_EXTENT,'999,999,999,999')       \"Next\",
   TO_CHAR(MAX_EXTENT,'999,999,999,999')        \"Max extents\",
   PCT_INCREASE                                 \"Pct increase\",
   HIGH_VALUE                                   \"High value\",
   HIGH_VALUE_LENGTH                            \"High value length\",
   LOGGING                                      \"Logging\"
FROM DBA_IND_PARTITIONS
   WHERE INDEX_OWNER = '$schema'
ORDER BY INDEX_NAME
";

      $text = "Select a partition for info about the parent index.";
      $link = "$scriptname?database=$database&schema=$schema&object_type=INDEX";
      DisplayTable($sql,$text,$link,$infotext);
      logit("   Link = $link");

      exit;

   }

# Show all for sequences

   if ($object_type eq "SEQUENCE") {

       $sql = "$copyright
SELECT
   SEQUENCE_NAME				\"Sequence name\",
   MIN_VALUE                                    \"Min value\",
   MAX_VALUE                                    \"Max value\",
   INCREMENT_BY                                 \"Increment by\",
   CYCLE_FLAG                                   \"Cycle flag\",
   ORDER_FLAG                                   \"Order flag\",
   CACHE_SIZE                                   \"Cache size\",
   LAST_NUMBER                                  \"Last number\"
FROM DBA_SEQUENCES
   WHERE SEQUENCE_OWNER = '$schema'
";
      $text = "Sequences owned by $schema..";
      DisplayTable($sql,$text);

      exit;

   }

# Show public synonym info

   if ($object_type eq "PUBLIC SYNONYMS") {

      $sql = "$copyright
SELECT
   SYNONYM_NAME		\"Synonym name\",
   TABLE_NAME		\"Object name\",
   TABLE_OWNER		\"Object owner\",
   DB_LINK		\"DB link\"
FROM DBA_SYNONYMS
   WHERE OWNER = 'PUBLIC'
   AND TABLE_OWNER = '$schema'
";
      my $text = "All public synonyms pointing to $schema objects.";
      my $link = "";
      my $infotext = "No public synonyms are pointing to $schema objects.";
      DisplayTable($sql,$text,$link,$infotext);
   }

# Default sql

      $sql = "$copyright
SELECT 
   OBJECT_NAME       			\"Object name\" 
FROM DBA_OBJECTS 
   WHERE OWNER = '$schema' 
   AND OBJECT_TYPE = '$object_type'
";

   $link = "$scriptname?database=$database&schema=$schema&object_type=$object_name";
   DisplayTable($sql,$text,$link);

   logit("Exit subroutine showObjects");

}

sub showSynonym {

   logit("Enter subroutine showSynonym");

   my ($sql,$text,$link);

# General synonym info

   $sql = "$copyright
SELECT 
   SYNONYM_NAME				\"Synonym name\", 
   TABLE_NAME				\"Object name\", 
   TABLE_OWNER				\"Table owner\", 
   DB_LINK				\"Database link\"
FROM DBA_SYNONYMS 
   WHERE SYNONYM_NAME = '$object_name' 
   AND OWNER = '$schema'
";
   $text = "";
   $link = "";
   DisplayTable($sql,$text,$link);

   logit("Exit subroutine showSynonym");

}

sub showTablespaces {

   logit("Enter subroutine showTablespaces");

   my ($sql,$text,$link,$temp_groups);

# Tablespace graph button

print <<"EOF";
<TABLE BORDER=0 CELLPADDING=0 CELLSPACING=0>
  <TR>
    <TD ALIGN=CENTER>
      <FORM METHOD="GET" ACTION="$scriptname">
        <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
        <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
        <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="TSGRAPH">
        <INPUT TYPE="SUBMIT" NAME="tsgraph" VALUE="Tablespace allocation graph">
      </FORM>
    </TD>
  </TR>
</TABLE>
EOF


#  Started adding for temporary tablespace groups.

   if ($oracle10) {
      $sql = "Select count(*) from dba_tablespace_groups";
      $temp_groups = recordCount($dbh,$sql);
      if ($temp_groups) {
         logit("There are temporary tablespace groups. Adding a button.");
         print <<"EOF";
<P>
<TABLE BORDER=0 CELLPADDING=0 CELLSPACING=0>
  <TR>
    <TD ALIGN=CENTER>
      <FORM METHOD="GET" ACTION="$scriptname">
        <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
        <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
        <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="TEMP_TS_GROUPS">
        <INPUT TYPE="SUBMIT" NAME="tsgraph" VALUE="Temp tablespace groups">
      </FORM>
    </TD>
  </TR>
</TABLE>
EOF
      }
   }

   $sql = "$copyright
SELECT
   TO_CHAR(SUM(BYTES),'999,999,999,999,999')	\"Total allocated space\"
FROM DBA_DATA_FILES
";

   $text = "";
   $link = "";
   DisplayTable($sql,$text,$link);

# General tablespace information

   $sql = "$copyright
SELECT
   TABLESPACE_NAME				\"Tablespace name\",
   TO_CHAR(INITIAL_EXTENT,'999,999,999,999')	\"Initial extent\",
   TO_CHAR(NEXT_EXTENT,'999,999,999,999')	\"Next extent\",
   TO_CHAR(MAX_EXTENTS,'999,999,999,999')	\"Max extents\",
   PCT_INCREASE					\"% increase\",
   STATUS					\"Status\",
   CONTENTS					\"Contents\"
   FROM DBA_TABLESPACES
ORDER BY TABLESPACE_NAME
";

   $sql = "$copyright
SELECT
   TABLESPACE_NAME						\"Tablespace name\",
   TO_CHAR(INITIAL_EXTENT,'999,999,999,999')			\"Initial extent\",
   TO_CHAR(NEXT_EXTENT,'999,999,999,999')			\"Next extent\",
   TO_CHAR(MAX_EXTENTS,'999,999,999,999')			\"Max extents\",
   TO_CHAR(MIN_EXTLEN,'999,999,999,999')			\"Minimum extent\",
   PCT_INCREASE							\"% increase\",
   STATUS							\"Status\",
   CONTENTS							\"Contents\",
   LOGGING							\"Logging?\"
FROM DBA_TABLESPACES
ORDER BY TABLESPACE_NAME
" if ($oracle8);

   $sql = "$copyright
SELECT
   TABLESPACE_NAME						\"Tablespace name\",
   TO_CHAR(INITIAL_EXTENT,'999,999,999,999')			\"Initial extent\",
   TO_CHAR(NEXT_EXTENT,'999,999,999,999')			\"Next extent\",
   TO_CHAR(MAX_EXTENTS,'999,999,999,999')			\"Max extents\",
   TO_CHAR(MIN_EXTLEN,'999,999,999,999')			\"Minimum extent\",
   PCT_INCREASE							\"% increase\",
   STATUS							\"Status\",
   CONTENTS							\"Contents\",
   LOGGING							\"Logging?\",
   EXTENT_MANAGEMENT						\"Ext. Mgmt\",
   ALLOCATION_TYPE						\"Alloc type\",
   PLUGGED_IN							\"Plugged?\"
FROM DBA_TABLESPACES
ORDER BY TABLESPACE_NAME
" if ($oracle8i);

   $sql = "$copyright
SELECT
   TABLESPACE_NAME						\"Tablespace name\",
   TO_CHAR(INITIAL_EXTENT,'999,999,999,999')			\"Initial extent\",
   TO_CHAR(NEXT_EXTENT,'999,999,999,999')			\"Next extent\",
   TO_CHAR(MAX_EXTENTS,'999,999,999,999')			\"Max extents\",
   TO_CHAR(MIN_EXTLEN,'999,999,999,999')			\"Minimum extent\",
   PCT_INCREASE							\"% increase\",
   STATUS							\"Status\",
   CONTENTS							\"Contents\",
   LOGGING							\"Logging?\",
   SEGMENT_SPACE_MANAGEMENT					\"Seg. Mgmt\",
   EXTENT_MANAGEMENT						\"Ext. Mgmt\",
   ALLOCATION_TYPE						\"Alloc type\",
   PLUGGED_IN							\"Plugged?\"
FROM DBA_TABLESPACES 
ORDER BY TABLESPACE_NAME
" if ($oracle9i);

   $sql = "$copyright
SELECT
   TABLESPACE_NAME						\"Tablespace name\",
   TO_CHAR(INITIAL_EXTENT,'999,999,999,999')			\"Initial extent\",
   TO_CHAR(NEXT_EXTENT,'999,999,999,999')			\"Next extent\",
   TO_CHAR(MAX_EXTENTS,'999,999,999,999')			\"Max extents\",
   TO_CHAR(MIN_EXTLEN,'999,999,999,999')			\"Minimum extent\",
   PCT_INCREASE							\"% increase\",
   STATUS							\"Status\",
   CONTENTS							\"Contents\",
   LOGGING							\"Logging?\",
   SEGMENT_SPACE_MANAGEMENT					\"Seg. Mgmt\",
   EXTENT_MANAGEMENT						\"Ext. Mgmt\",
   ALLOCATION_TYPE						\"Alloc type\",
   PLUGGED_IN							\"Plugged?\",
   BIGFILE							\"Bigfile?\",
   RETENTION							\"Retention\"
FROM DBA_TABLESPACES 
ORDER BY TABLESPACE_NAME
" if ($oracle10);

   $text = "Tablespace information: Database $database";
   $link = "$scriptname?database=$database&object_type=TSINFO";
   DisplayTable($sql,$text,$link);

   logit("Exit subroutine showTablespaces");

}

#sub tempTsGroups {
#
#   logit("Enter subroutine tempTsGroups");
#
#   my ($sql,$temp_group);
#
   

sub showTSinfo {

   logit("Enter subroutine showTSinfo");

   my ($sql,$cursor,$count,$foo,$text,$link,$infotext,$contents,$extent_management);
   my ($tempfiles_used);

   refreshButton();

   # Check to see if tablespace uses tempfiles, if OracleI.

   if ($oraclei) {

      $sql = "
SELECT CONTENTS, EXTENT_MANAGEMENT FROM DBA_TABLESPACES WHERE TABLESPACE_NAME = ?
";

      $cursor = $dbh->prepare($sql);
      $cursor->execute($object_name);
      ($contents,$extent_management) = $cursor->fetchrow_array;
      $cursor->finish;
      if (($contents eq "TEMPORARY") && ($extent_management eq "LOCAL")) {
         $tempfiles_used = "Yep";
      }
   }

   logit("Contents of tablespace $object_name are $contents, extent management $extent_management.");

# Tablespace information

   $sql = "$copyright
SELECT
   TABLESPACE_NAME                              \"Tablespace name\",
   TO_CHAR(INITIAL_EXTENT,'999,999,999,999')    \"Initial extent\",
   TO_CHAR(NEXT_EXTENT,'999,999,999,999')       \"Next extent\",
   TO_CHAR(MAX_EXTENTS,'999,999,999,999')       \"Max extents\",
   PCT_INCREASE                                 \"% increase\",
   STATUS                                       \"Status\",
   CONTENTS                                     \"Contents\"
   FROM DBA_TABLESPACES
WHERE TABLESPACE_NAME = '$object_name'
";

   $sql = "$copyright
SELECT
   DTS.TABLESPACE_NAME						\"Tablespace name\",
   TO_CHAR(DTS.INITIAL_EXTENT,'999,999,999,999')		\"Initial extent\",
   TO_CHAR(DTS.NEXT_EXTENT,'999,999,999,999')			\"Next extent\",
   TO_CHAR(DTS.MAX_EXTENTS,'999,999,999,999')			\"Max extents\",
   TO_CHAR(TSD.DFLMINLEN*$db_block_size,'999,999,999,999')	\"Minimum extent\",
   DTS.PCT_INCREASE						\"% increase\",
   DTS.STATUS							\"Status\",
   DTS.CONTENTS							\"Contents\",
   DTS.LOGGING							\"Logging?\"
FROM DBA_TABLESPACES DTS, SYS.TS\$ TSD
   WHERE DTS.TABLESPACE_NAME = '$object_name'
   AND TSD.NAME = '$object_name'
" if ($oracle8);

   $sql = "$copyright
SELECT
   DTS.TABLESPACE_NAME						\"Tablespace name\",
   TO_CHAR(DTS.INITIAL_EXTENT,'999,999,999,999')		\"Initial extent\",
   TO_CHAR(DTS.NEXT_EXTENT,'999,999,999,999')			\"Next extent\",
   TO_CHAR(DTS.MAX_EXTENTS,'999,999,999,999')			\"Max extents\",
   TO_CHAR(TSD.DFLMINLEN*$db_block_size,'999,999,999,999')	\"Minimum extent\",
   DTS.PCT_INCREASE						\"% increase\",
   DTS.STATUS							\"Status\",
   DTS.CONTENTS							\"Contents\",
   DTS.LOGGING							\"Logging?\",
   DTS.EXTENT_MANAGEMENT					\"Ext. Mgmt\",
   DTS.ALLOCATION_TYPE						\"Alloc type\",
   DTS.PLUGGED_IN						\"Plugged?\"
FROM DBA_TABLESPACES DTS, SYS.TS\$ TSD
   WHERE DTS.TABLESPACE_NAME = '$object_name'
   AND TSD.NAME = '$object_name'
" if ($oracle8i);

   $sql = "$copyright
SELECT
   DTS.TABLESPACE_NAME						\"Tablespace name\",
   TO_CHAR(DTS.INITIAL_EXTENT,'999,999,999,999')		\"Initial extent\",
   TO_CHAR(DTS.NEXT_EXTENT,'999,999,999,999')			\"Next extent\",
   TO_CHAR(DTS.MAX_EXTENTS,'999,999,999,999')			\"Max extents\",
   TO_CHAR(TSD.DFLMINLEN*$db_block_size,'999,999,999,999')	\"Minimum extent\",
   DTS.PCT_INCREASE						\"% increase\",
   DTS.STATUS							\"Status\",
   DTS.CONTENTS							\"Contents\",
   DTS.LOGGING							\"Logging?\",
   DTS.SEGMENT_SPACE_MANAGEMENT					\"Seg. Mgmt\",
   DTS.EXTENT_MANAGEMENT					\"Ext. Mgmt\",
   DTS.ALLOCATION_TYPE						\"Alloc type\",
   DTS.PLUGGED_IN						\"Plugged?\"
FROM DBA_TABLESPACES DTS, SYS.TS\$ TSD
   WHERE DTS.TABLESPACE_NAME = '$object_name'
   AND TSD.NAME = '$object_name'
" if ($oracle9i || $oracle10);

   $text = "General information: Tablespace $object_name";
   $link = "$scriptname?database=$database&object_type=TSDDL";
   DisplayTable($sql,$text,$link);

#  Started adding for temporary tablespace groups. 

#   if ($oracle10) {
#      $sql = "Select distinct group_name from dba_tablespace_groups where group_name = '$TMPTS'";
#      
#      $temp_group = 
#      if ($temp_group) {
#         logit("   The temporary tablespace for this user is a tablespace group.");

# Space allocation

   $sql = "$copyright
SELECT
   DF.TABLESPACE_NAME						\"Tablespace name\",
   TO_CHAR(DF.BYTES,'999,999,999,999,999,999')				\"Bytes allocated\",
   NVL(TO_CHAR(DF.BYTES-SUM(FS.BYTES),'999,999,999,999,999,999'),    
        TO_CHAR(DF.BYTES,'999,999,999,999,999,999'))			\"Bytes used\", 
   NVL(TO_CHAR(SUM(FS.BYTES),'999,999,999,999,999,999'),0)		\"Bytes free\",
   NVL(ROUND((DF.BYTES-SUM(FS.BYTES))*100/DF.BYTES),100)||'%'	\"Percent used\",
   NVL(ROUND(SUM(FS.BYTES)*100/DF.BYTES),0)||'%'			\"Percent free\" 
FROM DBA_FREE_SPACE FS,
   (SELECT TABLESPACE_NAME, SUM(BYTES) BYTES FROM DBA_DATA_FILES GROUP BY
TABLESPACE_NAME ) DF
WHERE FS.TABLESPACE_NAME (+) = DF.TABLESPACE_NAME
AND DF.TABLESPACE_NAME = '$object_name'
GROUP BY DF.TABLESPACE_NAME, DF.BYTES
ORDER BY \"Percent free\"
";

   # Added for temporary files which are managed locally. Space stats come from 
   # V$TEMP_EXTENT_POOL and V$TEMP_EXTENT_MAP. Oracle"I" only.

   if ($tempfiles_used) {
      logit("   Checking space for temp files");
      $sql = "$copyright
SELECT
   DF.TABLESPACE_NAME                                           \"Tablespace name\",
   TO_CHAR(DF.BYTES,'999,999,999,999')                          \"Bytes allocated\",
   NVL(TO_CHAR(SUM(FS.BYTES_USED),'999,999,999,999'),0)         \"Bytes used\",
   NVL(TO_CHAR(SUM(FS.BYTES_CACHED),'999,999,999,999'),0)	\"Bytes cached\",
   NVL(TO_CHAR(DF.BYTES-SUM(FS.BYTES_USED),'999,999,999,999'),
        TO_CHAR(DF.BYTES,'999,999,999,999'))                    \"Bytes free\",
   NVL(ROUND(SUM(FS.BYTES_USED)*100/DF.BYTES),0)||'%'           \"Percent used\",
   NVL(ROUND((DF.BYTES-SUM(FS.BYTES_USED))*100/DF.BYTES),100)||'%' \"Percent free\"
FROM V\$TEMP_EXTENT_POOL FS,
   (SELECT TABLESPACE_NAME, SUM(BYTES) BYTES FROM DBA_TEMP_FILES GROUP BY
TABLESPACE_NAME ) DF
WHERE FS.TABLESPACE_NAME (+) = DF.TABLESPACE_NAME
AND DF.TABLESPACE_NAME = '$object_name'
GROUP BY DF.TABLESPACE_NAME, DF.BYTES
ORDER BY \"Percent free\"
";
   }

   $text = "Space allocation";
   $link = "";
   DisplayTable($sql,$text,$link);

#   $sql = "
#SELECT 
#   ROUND(((B.BLOCKS*P.VALUE)/1024/1024),2)||'M'		\"Size\",
#           A.SID                                        \"Sid\",
#           A.SERIAL#					\"Serial#\",
#           A.USERNAME					\"Username\",
#           A.PROGRAM					\"Program\"
#    FROM SYS.V_\$SESSION A,
#           SYS.V_\$SORT_USAGE B,
#           SYS.V_\$PARAMETER P
#    WHERE B.TABLESPACE = '$object_name'
#    AND P.NAME  = 'db_block_size'
#    AND A.SADDR = B.SESSION_ADDR
#    ORDER BY B.TABLESPACE, B.BLOCKS
#";

   $sql = "
SELECT 
   TO_CHAR(B.BLOCKS*P.VALUE,'999,999,999,999,999')	\"Size\",
           A.SID                                        \"Sid\",
           A.SERIAL#					\"Serial#\",
           A.USERNAME					\"Username\",
           A.PROGRAM					\"Program\"
    FROM SYS.V_\$SESSION A,
           SYS.V_\$SORT_USAGE B,
           SYS.V_\$PARAMETER P
    WHERE B.TABLESPACE = '$object_name'
    AND P.NAME  = 'db_block_size'
    AND A.SADDR = B.SESSION_ADDR
    ORDER BY B.TABLESPACE, B.BLOCKS
";

   $text = "Temp segment usage";
   $link = "";
   $infotext = "No temp segments in use for this tablespace.";
   DisplayTable($sql,$text,$link);

# Fragmentation / general info

   $sql = "$copyright
SELECT
   A.FILE_NAME						\"File name\",
   A.FILE_ID						\"File #\",
   TO_CHAR(A.BYTES,'999,999,999,999')			\"Bytes\",
   TO_CHAR(NVL(MAX(B.BYTES),'0'),'999,999,999,999')	\"Largest free chunk\",
   TO_CHAR(NVL(MIN(B.BYTES),'0'),'999,999,999,999')	\"Smallest free chunk\",
   COUNT(*)						\"Pieces\"
FROM DBA_DATA_FILES A, DBA_FREE_SPACE B
   WHERE A.FILE_ID = B.FILE_ID(+)
   AND A.TABLESPACE_NAME = '$object_name'
   GROUP BY A.FILE_NAME, A.FILE_ID, A.BYTES
";

   $sql = "$copyright
SELECT
   A.FILE_NAME							\"File name\",
   A.FILE_ID							\"File #\",
   TO_CHAR(A.BYTES,'999,999,999,999')				\"Bytes\",
   TO_CHAR(NVL(MAX(B.BYTES),'0'),'999,999,999,999')		\"Largest free chunk\",
   TO_CHAR(NVL(MIN(B.BYTES),'0'),'999,999,999,999')		\"Smallest free chunk\",
   COUNT(*)							\"Pieces\",
   DECODE(A.AUTOEXTENSIBLE,
                           'YES','Yes',
                           'NO','No')				\"Xtend?\",
   TO_CHAR(A.MAXBYTES,'999,999,999,999')			\"Max bytes\",
   TO_CHAR(A.INCREMENT_BY*$db_block_size,'999,999,999,999')	\"Increment\"
FROM DBA_DATA_FILES A, DBA_FREE_SPACE B
   WHERE A.FILE_ID = B.FILE_ID(+)
   AND A.TABLESPACE_NAME = '$object_name'
   GROUP BY A.FILE_NAME, A.FILE_ID,
   A.BYTES,A.AUTOEXTENSIBLE,A.MAXBYTES,A.INCREMENT_BY
" if ($notoracle7);

   $text = "Tablespace (datafile) fragmentation";

   # Added for temporary files which are managed locally. Space stats come from 
   # V$TEMP_EXTENT_POOL and V$TEMP_EXTENT_MAP. Oracle"I" only.

   if ($tempfiles_used) {
      logit("   Checking space for temp files");
      $sql = "$copyright
SELECT 
   FILE_NAME							\"Tempfile name\",
   FILE_ID							\"File #\", 
   TO_CHAR(BYTES,'999,999,999,999')				\"Bytes\",
   DECODE(AUTOEXTENSIBLE,
                           'YES','Yes',
                           'NO','No')				\"Xtend?\",
   TO_CHAR(MAXBYTES,'999,999,999,999')			\"Max bytes\",
   TO_CHAR(INCREMENT_BY*$db_block_size,'999,999,999,999')	\"Increment\"
FROM DBA_TEMP_FILES
WHERE TABLESPACE_NAME = '$object_name'
ORDER BY FILE_NAME
";

   $text = "Temporary datafile information";

   }

   $link = "$scriptname?database=$database&object_type=DATAFILE";
   DisplayTable($sql,$text,$link);

   unless ($tempfiles_used) {

      print <<"EOF";
<TABLE BORDER=0 CELLPADDING=20>
  <TR>
    <TD VALIGN=TOP ALIGN=CENTER>
    <FONT FACE="$font" SIZE="$fontsize" COLOR="$fontcolor">
EOF

      $sql = "$copyright
SELECT DISTINCT
   TO_CHAR(BYTES,'999,999,999,999')		\"Extent size\",
   TO_CHAR(COUNT(*),'999,999,999,999')		\"# extents\"
FROM DBA_EXTENTS
   WHERE TABLESPACE_NAME = '$object_name'
GROUP BY BYTES 
ORDER BY 1 DESC
";

      $text = "Used extent sizes / counts.";
      DisplayTable($sql,$text);

      print <<"EOF";
    </TD>
    <TD VALIGN=TOP ALIGN=CENTER>
    <FONT FACE="$font" SIZE="$fontsize" COLOR="$fontcolor">
EOF


   $sql = "$copyright
SELECT DISTINCT
   TO_CHAR(BYTES,'999,999,999,999')		\"Extent size\",
   TO_CHAR(COUNT(*),'999,999,999,999')		\"# extents\"
FROM DBA_FREE_SPACE
   WHERE TABLESPACE_NAME = '$object_name'
GROUP BY BYTES 
ORDER BY 1 DESC
";

      $text = "Free extent sizes / counts.";
      DisplayTable($sql,$text);

      print <<"EOF";
          </TD>
        </TR>
      </TABLE>
EOF

   # Extent info for temp file based tablespaces

    } else {

   # Tempfile extent information..

#      $sql = "$copyright
#SELECT DISTINCT
#   TO_CHAR(BYTES_USED,'999,999,999,999')	\"Extent size\",
#   TO_CHAR(COUNT(*),'999,999,999,999')		\"# extents\"
#FROM V\$TEMP_EXTENT_POOL
#   WHERE TABLESPACE_NAME = '$object_name'
#   AND BYTES_USED > 0
#GROUP BY BYTES_USED
#ORDER BY 1 DESC
#";

   }

   unless ($tempfiles_used) {

# Added this to check for DBA_FREE_SPACE
# returning a null value if there is no
# free space

      $sql = "$copyright
SELECT MAX(BYTES)
   FROM DBA_FREE_SPACE
WHERE TABLESPACE_NAME = '$object_name'
";
      $cursor=$dbh->prepare($sql);
      $cursor->execute;
      $foo = $cursor->fetchrow_array;
      if ($foo) {
   

# Objects in the tablespace with next extent sizes larger than the largest
# free extent in the tablespace. Allocating a next extent for these objects
# will fail.

         $sql = "$copyright
SELECT 
   SEGMENT_NAME					\"Object name\", 
   OWNER					\"Owner\",
   TO_CHAR(NEXT_EXTENT,'999,999,999,999')	\"Next extent\"
FROM DBA_SEGMENTS
   WHERE TABLESPACE_NAME = '$object_name'
   AND NEXT_EXTENT > (SELECT MAX(BYTES) FROM DBA_FREE_SPACE
WHERE TABLESPACE_NAME = '$object_name')
";
         $text = "Objects that will fail to allocate a next extent";
         $link = "";
         $infotext = "No objects in $object_name will fail to allocate a next extent.";
         DisplayTable($sql,$text,$link,$infotext);
       } else {
         message("Warning: No objects can allocate an extent. Add a datafile.");
      }
      undef $foo;

# Objects in the tablespace that are approaching their max_extents limit.

      $sql = "$copyright
SELECT 
   SEGMENT_NAME					\"Object name\",
   OWNER					\"Owner\",
   SEGMENT_TYPE					\"Object type\",
   TO_CHAR(EXTENTS,'999,999,999,999')		\"Extents\",
   TO_CHAR(MAX_EXTENTS,'999,999,999,999')	\"Max extents\"
FROM DBA_SEGMENTS
   WHERE TABLESPACE_NAME = '$object_name'
   AND EXTENTS > (MAX_EXTENTS-25)
   AND SEGMENT_TYPE != 'CACHE'
";

      $text = "Objects that are approaching their max_extents limit";
      $link = "";
      $infotext = "No objects in $object_name have extents > ( max_extents - 25 )";
      DisplayTable($sql,$text,$link,$infotext);

# Display a button for a screen with a datafile fragmentation map.
  
      print "<P>";

      Button("$scriptname?database=$database&object_type=FRAGMAP&arg=$object_name&whereclause=tablespace TARGET=body","Fragmentation map","$headingcolor","CENTER","200");
      Button("$scriptname?database=$database&object_type=FRAGLIST&arg=$object_name&whereclause=tablespace TARGET=body","Extent listing","$headingcolor","CENTER","200");
      Button("$scriptname?database=$database&object_type=TSFILEGRAPH&schema=$object_name TARGET=body","Datafile information","$headingcolor","CENTER","200");
   } else {
      print "<P>";
      Button("$scriptname?database=$database&object_type=TSFILEGRAPH&schema=$object_name&tempfiles=yep TARGET=body","Datafile information","$headingcolor","CENTER","200");
   }

   $sql = "SELECT COUNT(*) FROM DBA_SEGMENTS WHERE TABLESPACE_NAME = '$object_name'";
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $count = $cursor->fetchrow_array;
   $cursor->finish;

   if ($count) {
      Button("$scriptname?database=$database&object_type=SHOWTSOBJECTS&arg=$object_name TARGET=body","Display $count object(s)","$headingcolor","CENTER","200");
   }

   logit("Exit subroutine showTSinfo");

}

sub showTSobjects {

   logit("Enter subroutine showTSobjects");

   my ($sql,$text,$link,$infotext);

   $sql = "$copyright
SELECT 
   A.SEGMENT_NAME					\"Object name\",
   A.SEGMENT_TYPE					\"Object type\",
   A.OWNER						\"Owner\",
   TO_CHAR(B.CREATED,'Month DD, YYYY - HH24:MI')		\"Created\",
   TO_CHAR(B.LAST_DDL_TIME,'Month DD, YYYY - HH24:MI')    \"Last DDL time\",
   TO_CHAR(A.BYTES,'999,999,999,999')			\"Bytes\",
   TO_CHAR(A.INITIAL_EXTENT,'999,999,999,999')		\"Initial extent\",
   TO_CHAR(A.NEXT_EXTENT,'999,999,999,999')		\"Next extent\",
   TO_CHAR(A.EXTENTS,'999,999,999,999')			\"Extents\"
FROM DBA_SEGMENTS A, DBA_OBJECTS B
   WHERE A.TABLESPACE_NAME = '$object_name'
   AND A.SEGMENT_NAME = B.OBJECT_NAME
   AND A.SEGMENT_TYPE = B.OBJECT_TYPE
   AND A.OWNER = B.OWNER
ORDER BY A.OWNER, A.SEGMENT_TYPE, A.SEGMENT_NAME
";
   $text = "Object list for tablespace $object_name";
   $link = "";
   $infotext = "Tablespace $object_name has no objects.";
   ObjectTable($sql,$text,$infotext);

   logit("Exit subroutine showTSobjects");

}

sub sessionWaitByEvent {

   logit("Enter subroutine sessionWaitByEvent");

   my ($sql,$text,$link,$infotext);

   refreshButton();

   $sql = "$copyright
SELECT
   EVENT		\"Waiting on\",
   MAX(SECONDS_IN_WAIT)	\"Seconds waiting\"
FROM V\$SESSION_WAIT
   GROUP BY EVENT
   ORDER BY 2 DESC
";
   $text = "Session wait information by event / time.";
   $link = "";
   $infotext = "There are no sessions in a wait state.";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine sessionWaitByEvent");
}

sub sessionWait {

   logit("Enter subroutine sessionWait");

   my ($sql,$text,$link,$infotext,$refreshrate);

   $refreshrate = $ENV{'AUTO_REFRESH'} || "10";

   unless ($norefreshbutton) {

      print <<"EOF";
  <FORM METHOD="POST" ACTION="$scriptname">
    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
    <INPUT TYPE=HIDDEN NAME=database    VALUE=$database>
    <INPUT TYPE=HIDDEN NAME=object_type VALUE=$object_type>
    <INPUT TYPE=HIDDEN NAME=arg         VALUE=$object_name>
    <INPUT TYPE=HIDDEN NAME=refreshrate VALUE=$refreshrate>
    <INPUT TYPE=SUBMIT NAME=foobar      VALUE=\"AutoRefresh ($refreshrate)\">
  </FORM>
  <P>
EOF

   }

   $sql = "$copyright
SELECT 
   VS.USERNAME						\"Username\",
   VS.OSUSER						\"OS user\",
   VSW.SID						\"SID\",
   VSW.EVENT						\"Waiting on..\",
   TO_CHAR(VSW.SECONDS_IN_WAIT,'999,999,999,999')	\"Seconds waiting\",
   TO_CHAR(VSW.SECONDS_IN_WAIT/60,'999,999,999,999')	\"Minutes waiting\",
   NVL(VSA.SQL_TEXT,'No SQL')				\"SQL text\"
FROM V\$SESSION_WAIT VSW,
     V\$SQLAREA VSA,
     V\$SESSION VS
WHERE VS.STATUS = 'ACTIVE'
AND VSW.SID = VS.SID
AND VS.USERNAME IS NOT NULL
AND VS.SQL_ADDRESS = VSA.ADDRESS
ORDER BY VSW.SECONDS_IN_WAIT DESC
";

   $text = "Session wait information for active sessions with SQL.";
   $link = "";
   $infotext = "There are no sessions in a wait state.";
   DisplayTable($sql,$text,$link,$infotext);

   $sql = "$copyright
SELECT 
   VS.USERNAME						\"Username\",
   VS.OSUSER						\"OS user\",
   VSW.SID						\"SID\",
   VSW.EVENT						\"Waiting on..\",
   TO_CHAR(VSW.SECONDS_IN_WAIT,'999,999,999,999')	\"Seconds waiting\",
   TO_CHAR(VSW.SECONDS_IN_WAIT/60,'999,999,999,999')	\"Minutes waiting\"
FROM V\$SESSION_WAIT VSW,
     V\$SESSION VS
WHERE VS.STATUS = 'ACTIVE'
AND VSW.SID = VS.SID
AND VS.USERNAME IS NOT NULL
AND VS.SQL_ADDRESS NOT IN (
   SELECT ADDRESS FROM V\$SQLAREA
) 
ORDER BY VSW.SECONDS_IN_WAIT DESC
";

   $text = "Session wait information for active sessions with no SQL available.";
   $link = "";
   $infotext = "";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine sessionWait");
}

sub showFile {

   logit("Enter subroutine showFile");

   my ($sql,$text,$link,$infotext,$count,$tempfile);
   my ($statview,$fileview,$dbaview,$string);

   # Find out if file is a datafile or a tempfile, if OracleI.

   if ($oraclei) {

      $sql = "
SELECT * FROM V\$TEMPFILE WHERE NAME = '$object_name'
";

      $tempfile = recordCount($dbh,$sql);

   }

   if ($tempfile) {
      $statview = "V\$TEMPSTAT";
      $fileview = "V\$TEMPFILE";
      $dbaview  = "DBA_TEMP_FILES";
      $string   = "tempfiles";
   } else {
      $statview = "V\$FILESTAT";
      $fileview = "V\$DATAFILE";
      $dbaview  = "DBA_DATA_FILES";
      $string   = "datafiles";
   }

   # Do not show button for tempfiles.

   unless ($tempfile) {

# Display a button for a screen with a datafile fragmentation map.

      print <<"EOF";
<TABLE BORDER=0 CELLPADDING=0 CELLSPACING=0>
  <TR>
    <TD ALIGN=CENTER>
      <FORM METHOD="GET" ACTION="$scriptname">
        <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
        <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
        <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="FRAGMAP">
        <INPUT TYPE="HIDDEN" NAME="arg" VALUE="$object_name">
        <INPUT TYPE="HIDDEN" NAME="whereclause" VALUE="datafile">
        <INPUT TYPE="SUBMIT" NAME="fragmap" VALUE="Fragmentation map">
      </FORM>
    </TD>
  </TR>
</TABLE>
EOF

   }

# Specific datafile information

   $sql = "$copyright
SELECT 
   B.FILE_NAME					\"File name\",
   TO_CHAR(A.CREATE_BYTES,'999,999,999,999')	\"Creation size\",
   TO_CHAR(A.BYTES,'999,999,999,999')		\"Current size\",
   TO_CHAR(B.BLOCKS,'999,999,999,999')		\"Blocks\",
   B.TABLESPACE_NAME				\"Tablespace_name\",
   B.STATUS					\"Status\"
FROM $fileview A, $dbaview B
   WHERE B.FILE_NAME = '$object_name'
   AND A.FILE# = B.FILE_ID
";
   $text = "General information";
   $link = "";
   DisplayTable($sql,$text,$link);

   $sql = "$copyright
SELECT 
   TO_CHAR(A.PHYRDS,'999,999,999,999,999,999,999')			\"Physical reads#\",
   TO_CHAR(A.PHYWRTS,'999,999,999,999,999,999,999')			\"Physical writes#\",
   TO_CHAR(A.PHYBLKRD*$db_block_size,'999,999,999,999,999,999,999')	\"Bytes read\",
   TO_CHAR(A.PHYBLKWRT*$db_block_size,'999,999,999,999,999,999,999')	\"Bytes written\"
FROM $statview A, $dbaview B
   WHERE B.FILE_NAME = '$object_name'
   AND A.FILE# = B.FILE_ID
";
   $text = "I/O stats since database startup";
   $link = "";
   DisplayTable($sql,$text,$link);

#   $text = "Historical I/O stats.";
#   DisplayGraph("dbfile",$object_name,$text);

   $sql = "$copyright
SELECT 
   NVL(TO_CHAR(NEXT_EXTENT,'999,999,999,999'),'n/a')	\"Next extent\"
FROM DBA_TABLESPACES
    WHERE TABLESPACE_NAME =  
(SELECT 
   TABLESPACE_NAME FROM $dbaview
WHERE FILE_NAME = '$object_name')
";

   $text = "Next extent size of tablespace";
   $link = "";
   DisplayTable($sql,$text,$link);

   unless ($tempfile) {
   
      $sql = "$copyright
SELECT 
   TO_CHAR(BYTES,'999,999,999,999')		\"Chunk size (bytes)\",
   TO_CHAR(BLOCKS,'999,999,999,999')		\"Blocks\"
FROM DBA_FREE_SPACE
   WHERE FILE_ID  = 
(SELECT 
   FILE_ID FROM DBA_DATA_FILES 
      WHERE FILE_NAME = '$object_name')
      AND ROWNUM <= 10
   ORDER BY BYTES DESC
";
      $text = "Free space (Top ten)";
      $link = "";
      $infotext = "There are no free chunks of data in this datafile.";
      DisplayTable($sql,$text,$link,$infotext);

      $sql = "$copyright
SELECT DISTINCT
   SEGMENT_NAME					\"Segment name\",
   SEGMENT_TYPE					\"Segment type\",
   OWNER					\"Owner\",
   TABLESPACE_NAME				\"Tablespace name\"
FROM DBA_EXTENTS
   WHERE FILE_ID = (
SELECT FILE_ID FROM DBA_DATA_FILES
   WHERE FILE_NAME = '$object_name')
";

      $text = "Objects which have extents in this datafile.";
      $infotext = "There are no objects with extents in this datafile.";
      ObjectTable($sql,$text,$infotext);

   }

   logit("Exit subroutine showFile");

}

sub doSQL {

   logit("Enter subroutine doSQL"); 

   my $dbhandle = shift;
   my $sql	= shift;
   my $error;

   $error = $dbhandle->do($sql);

   return($error);

   logit("Exit subroutine doSQL");

}

sub runSQL {

   logit("Enter subroutine runSQL");

   my ($dbhandle,$sql,$cursor,$rows,$text,$link,$infotext,@statements,$statement,$error);

   $dbhandle = shift;
   $_ = shift;
   $_ = $object_name unless $_;
# Get rid of trailing whitespace
   s/\s+$//;
   @statements = split /;/;
   foreach $_ (@statements) {
# Get rid of leading whitespace and newlines
      s/^\s+//;

   logit("SQL = $_");

# If the command is "DESCRIBE"
   if (/^desc/i) {
      @_ = split;
      Describe("$_[1]");
      next;
   }

   loginfo("   SQL:\n$_");
      
print <<"EOF";
<TABLE BGCOLOR='$bordercolor' WIDTH="100" CELLPADDING="1" CELLSPACING="0" BORDER="0" ALIGN="CENTER">
  <TR>
    <TD VALIGN="TOP">
      <TABLE BGCOLOR="$headingcolor" WIDTH="100%" CELLPADDING="2" CELLSPACING="1" BORDER="0">
        <TR ALIGN="LEFT">
          <TD><B><FONT SIZE="2">
          <PRE>
$_</PRE>
          </TD>
        </TR>
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF
# Check to see if it is a select statement.
      if (/^SELECT/i) {
         $text = "";
         $link ="";
         $infotext = "No rows to display.";
         $error = DisplayTable($_,$text,$link,$infotext,$rows,$dbhandle);
         logit("   DisplayTable returned $error") if $error;
         unless ($error =~ /^\d+$/) {
            message("Select statement failed: $error\n");
         }
         print "<BR>\n";
# If not a select, then "do" the statement
      } else {
         $cursor=$dbhandle->do($_);
         if ( ! $cursor) {
            $_ = $DBI::errstr;
# Get rid of unneccessary DBD::Oracle message
            s/DBD: //;
            s/\(DBD.*\)//;
            message("SQL error:<BR>$_\n");
         } else {
            message("SQL statement executed successfully.\n");
            $rows = $dbhandle->rows;
            if ($rows > 0) {
               message("$rows rows affected.\n");
            }
         }
      }
   print "<HR WIDTH=\"10%\">\n";
   }

   logit("Exit subroutine runSQL");

}

sub runExplainPlan {

   logit("Enter subroutine runExplainPlan");

   my ($sql,$cursor,$count,$text,$link,$infotext,@row,$title,$heading,$explainsql,$rc);
   my ($utlxplan733,$utlxplan8,$operation,$options,$objname,$cost,$table_color,$foo);
   my ($objtype,$objowner,$card,$bytes,$other,$maxlength,$line,$numspaces,$i,$linelength);
   my ($optimizer,$utlxplan8i,$utlxplan9i,$utlxplan10);

$utlxplan733 = "
create table PLAN_TABLE (
        statement_id    varchar2(30),
        timestamp       date,
        remarks         varchar2(80),
        operation       varchar2(30),
        options         varchar2(30),
        object_node     varchar2(128),
        object_owner    varchar2(30),
        object_name     varchar2(30),
        object_instance numeric,
        object_type     varchar2(30),
        optimizer       varchar2(255),
        search_columns  numeric,
        id              numeric,
        parent_id       numeric,
        position        numeric,
        cost            numeric,
        cardinality     numeric,
        bytes           numeric,
        other_tag       varchar2(255),
        other           long)
";

$utlxplan8 = "
create table PLAN_TABLE (
        statement_id    varchar2(30),
        timestamp       date,
        remarks         varchar2(80),
        operation       varchar2(30),
        options         varchar2(30),
        object_node     varchar2(128),
        object_owner    varchar2(30),
        object_name     varchar2(30),
        object_instance numeric,
        object_type     varchar2(30),
        optimizer       varchar2(255),
        search_columns  number,
        id              numeric,
        parent_id       numeric,
        position        numeric,
        cost            numeric,
        cardinality     numeric,
        bytes           numeric,
        other_tag       varchar2(255),
        partition_start varchar2(255),
        partition_stop  varchar2(255),
        partition_id    numeric,
        other           long)
";

$utlxplan8i = "
create table PLAN_TABLE (
        statement_id    varchar2(30),
        timestamp       date,
        remarks         varchar2(80),
        operation       varchar2(30),
        options         varchar2(30),
        object_node     varchar2(128),
        object_owner    varchar2(30),
        object_name     varchar2(30),
        object_instance numeric,
        object_type     varchar2(30),
        optimizer       varchar2(255),
        search_columns  number,
        id              numeric,
        parent_id       numeric,
        position        numeric,
        cost            numeric,
        cardinality     numeric,
        bytes           numeric,
        other_tag       varchar2(255),
        partition_start varchar2(255),
        partition_stop  varchar2(255),
        partition_id    numeric,
        other           long,
        distribution    varchar2(30))
";

$utlxplan9i = "
create table PLAN_TABLE (
        statement_id    varchar2(30),
        timestamp       date,
        remarks         varchar2(80),
        operation       varchar2(30),
        options         varchar2(255),
        object_node     varchar2(128),
        object_owner    varchar2(30),
        object_name     varchar2(30),
        object_instance numeric,
        object_type     varchar2(30),
        optimizer       varchar2(255),
        search_columns  number,
        id              numeric,
        parent_id       numeric,
        position        numeric,
        cost            numeric,
        cardinality     numeric,
        bytes           numeric,
        other_tag       varchar2(255),
        partition_start varchar2(255),
        partition_stop  varchar2(255),
        partition_id    numeric,
        other           long,
        distribution    varchar2(30),
        cpu_cost        numeric,
        io_cost         numeric,
        temp_space      numeric)
";

$utlxplan10 = "
create table PLAN_TABLE (
        statement_id       varchar2(30),
        plan_id            number,
        timestamp          date,
        remarks            varchar2(4000),
        operation          varchar2(30),
        options            varchar2(255),
        object_node        varchar2(128),
        object_owner       varchar2(30),
        object_name        varchar2(30),
        object_alias       varchar2(65),
        object_instance    numeric,
        object_type        varchar2(30),
        optimizer          varchar2(255),
        search_columns     number,
        id                 numeric,
        parent_id          numeric,
        depth              numeric,
        position           numeric,
        cost               numeric,
        cardinality        numeric,
        bytes              numeric,
        other_tag          varchar2(255),
        partition_start    varchar2(255),
        partition_stop     varchar2(255),
        partition_id       numeric,
        other              long,
        distribution       varchar2(30),
        cpu_cost           numeric,
        io_cost            numeric,
        temp_space         numeric,
        access_predicates  varchar2(4000),
        filter_predicates  varchar2(4000),
        projection         varchar2(4000),
        time               numeric,
        qblock_name        varchar2(30))
";

# Connect to database using ID of the owner of the SQL passed. This will 
# actually mean that the Oracletool that created the menu is (was) connected
# as the user with "SELECT ANY TABLE" privileges while the connection in 
# the body does not need that level of access. Therefore, any clicks on the
# menu buttons will reconnect as the main user, not the SQL owner. Yeah, whatever.
# Have I mentioned that CGI bites?

   my $data_source = "dbi:Oracle:$database";

   logit("Connecting to database $database as $explainschema to run explain plan.");

   my $dbh = DBI->connect($data_source,$explainschema,$explainpassword,{PrintError=>0});
   if (! $dbh) {
      $object_name =~ s/"/&quot;/g;
      $object_name =~ s/>/&gt;/g;
      $object_name =~ s/</&lt;/g;
      if ($explainschema) {
         ErrorPage("Could not connect as $explainschema, password $explainpassword.<BR>$DBI::errstr");
         exit;
      } else {
         ErrorPage("Please enter a username and password.");
         exit;
      }
   }

# OK, we're connected, let's display the header.

   Header($title,$heading,$font,$fontsize,$fontcolor,$bgcolor);

# Now, check for a plan table under this schema.

   $sql = "$copyright
SELECT COUNT(*)
   FROM USER_TABLES
WHERE TABLE_NAME = 'PLAN_TABLE'
";

   $cursor=$dbh->prepare($sql);
   $cursor->execute;
   $count = $cursor->fetchrow_array;
   $cursor->finish;
   if (! $count) {
# No plan table exists. Let's create one.
      logit("No explain plan exists, Oracletool will create one, if possible.");
      if ($oracle7) {
         $sql = $utlxplan733;
         logit("Creating an Oracle7 plan table for user $explainschema with SQL = $sql");
      }
      if ($oracle8) {
         $sql = $utlxplan8;
         logit("Creating an Oracle8 plan table for user $explainschema with SQL = $sql");
      }
      if ($oracle8i) {
         $sql = $utlxplan8i;
         logit("Creating an Oracle8i plan table for user $explainschema with SQL = $sql");
      }
      if ($oracle9i) {
         $sql = $utlxplan9i;
         logit("Creating an Oracle9i plan table for user $explainschema with SQL = $sql");
      }
      if ($oracle10) {
         $sql = $utlxplan10;
         logit("Creating an Oracle10 plan table for user $explainschema with SQL = $sql");
      }
      $cursor = $dbh->do($sql);
      if (! $cursor) {
         message("Could not create PLAN_TABLE.<BR>$DBI::errstr\n");
         $dbh->disconnect;
         exit;
      }
      message("$explainschema did not have a PLAN_TABLE required for explain plan. Oracletool has created this table for you.");
   }

# Got a connection, and a PLAN_TABLE exists.

# Set the statement_id to a unique identifier.

   $statement_id = "Oracletool.$$";

   $explainsql	= $object_name;
# Get rid of ;, if one exists
   $explainsql =~ s/;$//;
   $explainsql = "EXPLAIN PLAN SET STATEMENT_ID = '$statement_id' INTO PLAN_TABLE FOR $explainsql";
   logit("Explain SQL = $explainsql");
   $cursor=$dbh->do($explainsql);
   if ( ! $cursor) { 
      message("Could not execute explain plan.<BR>$DBI::errstr\n");
      Footer();
   } else {
      text("Explain plan executed successfully.\n");
   }

   $sql = "$copyright
SELECT
   DISTINCT OPTIMIZER
FROM PLAN_TABLE
   WHERE STATEMENT_ID = '$statement_id'
";
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $optimizer = $cursor->fetchrow_array;
   $cursor->finish;

   text("Optimizer mode is $optimizer.");

   $sql = "$copyright
SELECT 
   LPAD(' ',2*LEVEL-1)||OPERATION ,
   OPTIONS,
   OBJECT_NAME,
   OBJECT_TYPE,
   OBJECT_OWNER,
   COST,
   CARDINALITY,
   BYTES,
   OTHER_TAG
FROM PLAN_TABLE
START WITH ID=0 
   AND STATEMENT_ID = '$statement_id'
CONNECT BY PRIOR ID = PARENT_ID 
   AND STATEMENT_ID = '$statement_id'
ORDER BY ID
";
   $cursor=$dbh->prepare($sql);
   $cursor->execute;
   $maxlength = 0;
   logit("Statement ID is $statement_id");
   while (($operation,$options,$objname,$objtype,$objowner,$cost,$card,$bytes,$other) = $cursor->fetchrow_array) {
      $line = "$operation $options $objname";
      if ($cost) {
         $line .= "Cost: $cost "; 
      }
      if (length($line) > $maxlength) {
         $maxlength = length($line);
         logit("   Explain plan max line length is $maxlength");
      }
   }
   $cursor->finish;   
   print "<TABLE BORDER=0>\n";
   $cursor=$dbh->prepare($sql);
   $cursor->execute;
   while (($operation,$options,$objname,$objtype,$objowner,$cost,$card,$bytes,$other) = $cursor->fetchrow_array) {
      logit("   Explain: $operation,$options,$objname,$objtype,$objowner,$cost,$card,$bytes,$other");
      if ($foo) {
         $table_color = "$headingcolor";
         $foo--;
      } else {
         $table_color = "$cellcolor";
         $foo++
      }
      $linelength = length("$operation $options $other $objname");
         print "<TR BGCOLOR=$table_color><TD><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><PRE><B>$operation $options $other ";
#      if ($objowner && $objname && $objtype) {
#         print "<A HREF=$scriptname?database=$database&schema=$objowner&object_type=$objtype&arg=$objname>$objowner.$objname</A>";
#      } elsif ($objname) {
#         print "$objname";
#      }
      print "$objowner.$objname" if ($objowner && $objname);
      if ($cost) {
         $numspaces = $maxlength-$linelength+5;
         for($i = 0; $i <= $numspaces; $i++) {
           print " ";
         } 
         print "Cardinality: $card " if $card;
         print "Cost: $cost " if $cost;
      }
      print "</TD></TR>\n";
      $cost = 0;
   }
   $cursor->finish;

   print "</TABLE>\n";

   $sql = "$copyright
DELETE FROM PLAN_TABLE 
   WHERE STATEMENT_ID = '$statement_id'
";
   $rc = $dbh->do($sql);
   unless ($rc) {
      $dbh->disconnect;
      ErrorPage("Could not delete records from PLAN_TABLE");
   }
   $dbh->disconnect;
   Footer();

   logit("Exit subroutine runExplainPlan");
}

sub enterWorksheet {

   logit("Enter subroutine enterWorksheet");

   my ($sql);

   message("Connected to $database as $schema.");
   text("Enter or paste the SQL you wish to execute.<BR>Terminate statements with a <B>';'</B> if entering multiple statements.");
   print <<"EOF";
<FORM METHOD="POST" ACTION="$scriptname">
<FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
<INPUT TYPE=HIDDEN NAME=object_type VALUE=RUNSQL>
<INPUT TYPE=HIDDEN NAME=database VALUE=$database>
<INPUT TYPE=HIDDEN NAME=schema VALUE=$schema>
<TEXTAREA NAME=arg ROWS=$textarea_h COLS=$textarea_w WRAP=OFF></TEXTAREA>
<P>
</B>
<INPUT TYPE=SUBMIT VALUE="Execute">
</FORM>
EOF

   logit("Exit subroutine enterWorksheet");

}

sub sqlAreaList {

   logit("Enter subroutine sqlAreaList");

   my ($sql,$text,$link,$infotext);

   $sql = "$copyright
SELECT
   DU.USERNAME                  \"Username\",
   COUNT(SQL_TEXT)              \"# Entries\"
FROM DBA_USERS DU, V\$SQL VSA
   WHERE DU.USER_ID = VSA.PARSING_SCHEMA_ID
GROUP BY USERNAME,PARSING_SCHEMA_ID
ORDER BY 2 DESC
";

   $text = "The following users have SQL in the shared SQL area. Choose a user to display the parsed SQL.";
   $link = "$scriptname?database=$database&object_type=SQLAREALISTBYUSER";
   $infotext = "There are no entries in the shared SQL area";
   DisplayTable($sql,$text,$link,$infotext);

   $sql = "
SELECT
   TO_CHAR(EXECUTIONS,'999,999,999,999')						\"Executions#\",
   TO_CHAR(ROWS_PROCESSED,'999,999,999,999')						\"Rows processed\",
   TO_CHAR(DISK_READS / DECODE(EXECUTIONS,0,1, EXECUTIONS) / 50,'999,999,999,999')	\"Disk reads#\",
   SQL_TEXT										\"SQL text\"
FROM V\$SQLAREA
   WHERE EXECUTIONS > 1000
ORDER BY 1 DESC
";
   
   $text = "SQL in the shared SQL area with # executions > 1000";
   $link = "";
   $infotext = "There are no statements with # executions > 1000.";
   DisplayTable($sql,$text,$link,$infotext);

   $sql = "
SELECT
   TO_CHAR(EXECUTIONS,'999,999,999,999')						\"Executions#\",
   TO_CHAR(ROWS_PROCESSED,'999,999,999,999')						\"Rows processed\",
   TO_CHAR(DISK_READS / DECODE(EXECUTIONS,0,1, EXECUTIONS) / 50,'999,999,999,999')	\"Disk reads#\",
   SQL_TEXT										\"SQL text\"
FROM V\$SQLAREA
   WHERE DISK_READS / DECODE(EXECUTIONS,0,1, EXECUTIONS) / 50 > 100
ORDER BY 1 DESC
";
   
   $text = "SQL in the shared SQL area with high percentage of disk reads compared to executions.<br>(disk reads / executions) / 50 > 100";
   $link = "";
   $infotext = "There are no statements with a high percentage of disk reads compared to executions.";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine sqlAreaList");

}


sub sqlAreaListByUser {

   logit("Enter subroutine sqlAreaListByUser");

   my ($sql,$cursor,$text,$link,$infotext);

   $sql = "$copyright
SELECT
      SQL_ID			\"Explain plan\",
      DECODE(COMMAND_TYPE,
        '0','None',
        '1','Create table',
        '2','Insert',
        '3','Select',
        '4','Create cluster',
        '5','Alter cluster',
        '6','Update',
        '7','Delete',
        '8','Drop cluster',
        '9','Create index',
        '10','Drop index',
        '11','Alter index',
        '12','Drop table',
        '13','Create sequence',
        '14','Alter sequence',
        '15','Alter table',
        '16','Drop sequence',
        '17','Grant',
        '18','Revoke',
        '19','Create synonym',
        '20','Drop synonym',
        '21','Create view',
        '22','Drop view',
        '23','Validate index',
        '24','Create procedure',
        '25','Alter procedure',
        '26','Lock table',
        '27','No operation in progress',
        '28','Rename',
        '29','Comment',
        '30','Audit',
        '31','Noaudit',
        '32','Create database link',
        '33','Drop database link',
        '34','Create database',
        '35','Alter database',
        '36','Create rollback segment',
        '37','Alter rollback segment',
        '38','Drop rollback segment',
        '39','Create tablespace',
        '40','Alter tablespace',
        '41','Drop tablespace',
        '42','Alter session',
        '43','Alter user',
        '44','Commit',
        '45','Rollback',
        '46','Savepoint',
        '47','PL/SQL Execute',
        '48','Set transaction',
        '49','Alter system switch log',
        '50','Explain',
        '51','Create user',
        '52','Create role',
        '53','Drop user',
        '54','Drop role',
        '55','Set role',
        '56','Create schema',
        '57','Create control file',
        '58','Alter tracing',
        '59','Create trigger',
        '60','Alter trigger',
        '61','Drop trigger',
        '62','Analyze table',
        '63','Analyze index',
        '64','Analyze cluster',
        '65','Create profile',
        '66','Drop profile',
        '67','Alter profile',
        '68','Drop procedure',
        '69','Drop procedure',
        '70','Alter resource cost',
        '71','Create snapshot log',
        '72','Alter snapshot log',
        '73','Drop snapshot log',
        '74','Create snapshot',
        '75','Alter snapshot',
        '76','Drop snapshot',
        '79','Alter role',
        '85','Truncate table',
        '86','Truncate cluster',
        '88','Alter view',
        '91','Create function',
        '92','Alter function',
        '93','Drop function',
        '94','Create package',
        '95','Alter package',
        '96','Drop package',
        '97','Create package body',
        '98','Alter package body',
        '99','Drop package body')		\"Command type\",
   TO_CHAR(EXECUTIONS,'999,999,999,999')	\"Executions\",
   TO_CHAR(ROWS_PROCESSED,'999,999,999,999')	\"Rows processed\",
   TO_CHAR(DISK_READS,'999,999,999,999')	\"Disk reads\",
   TO_CHAR(SORTS,'999,999,999,999')		\"Sorts\",
   OPTIMIZER_MODE				\"Optimizer mode\",
   SQL_TEXT					\"SQL text\"
FROM V\$SQLAREA
   WHERE PARSING_SCHEMA_ID = 
(SELECT USER_ID FROM DBA_USERS 
   WHERE USERNAME = '$object_name')
ORDER BY 2 DESC, 4 DESC, 3 DESC, 5 DESC
";

   logit($sql);

   $text = " SQL for user $object_name in the shared SQL area.";
   $link = "$scriptname?database=$database&object_type=SQLINFO";
   $infotext = "There are no entries in the shared SQL area for user $object_name";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine sqlAreaListByUser");

}

sub enterExplainPlan {

   logit("Enter subroutine enterExplainPlan");

   my ($sql,$cursor,$count,$text,$link,$infotext);
   my ($owner,$table_name,$title,$heading);

   Header($title,$heading,$font,$fontsize,$fontcolor,$bgcolor);

   if ($explainschema) {
print <<"EOF";
SQL belongs to user $explainschema<BR>
Edit SQL and proceed
<FORM METHOD="POST" ACTION="$scriptname">
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE=HIDDEN NAME=object_type VALUE=RUNEXPLAINPLAN>
  <INPUT TYPE=HIDDEN NAME=database VALUE=$database>
  <INPUT TYPE=HIDDEN NAME=explainschema VALUE=$explainschema>
  <TEXTAREA NAME=arg ROWS=$textarea_h COLS=$textarea_w WRAP=SOFT>$object_name</TEXTAREA>
<P>Enter password for user $explainschema<P>
  <INPUT TYPE=PASSWORD NAME=explainpassword SIZE=20>
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Run explain plan">
</FORM>
EOF
   } else {
      print <<"EOF";
Enter SQL below
<FORM METHOD="POST" ACTION="$scriptname">
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE=HIDDEN NAME=object_type VALUE=RUNEXPLAINPLAN>
  <INPUT TYPE=HIDDEN NAME=database VALUE=$database>
  <FONT FACE="$font" SIZE="$fontsize">
  <TEXTAREA NAME=arg ROWS=$textarea_h COLS=$textarea_w WRAP=SOFT>$object_name</TEXTAREA>
  <TABLE BORDER=0>
    <TR>
      <TD ALIGN=CENTER>
        <FONT FACE="$font" SIZE="$fontsize" COLOR="$fontcolor">
        Enter user to run SQL<BR>
          <INPUT TYPE=TEXT NAME=explainschema SIZE=20 MAXLENGTH=40>
      </TD>
      <TD ALIGN=CENTER>
        <FONT FACE="$font" SIZE="$fontsize" COLOR="$fontcolor">
        Enter password for user<BR>
          <INPUT TYPE=PASSWORD NAME=explainpassword SIZE=20>
      </TD>
    </TR>
  </TABLE>
  <BR>
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Run explain plan">
</FORM>
EOF
   }

   logit("Exit subroutine enterExplainPlan");

exit;
}

sub ASMinfo {

   logit("Enter subroutine ASMinfo");

   my ($sql,$text,$link,$infotext);

   $sql = "
Select
   name						\"Name\",
   sector_size					\"Sector size\",
   block_size					\"Block size\",
   allocation_unit_size				\"Alloc unit size\",
   state					\"State\",
   type						\"Redundancy type\",
   to_char(total_mb,'999,999,999,999,999')	\"Size (MB)\",
   to_char(free_mb,'999,999,999,999,999')	\"Free (MB)\",
   to_char(100-(free_mb*100/total_mb),'999.99')	\"Percent used\",
   offline_disks				\"Offline disks\",
   decode(unbalanced,'Y','Yes','N','No')	\"Unbalanced\"
from v\$asm_diskgroup
";

   $text = "ASM disk group(s)";
   $link = "$scriptname?database=$database&object_type=ASMDISKS";
   $infotext = "";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine ASMinfo");

}

sub bindVars {

   logit(" Enter subroutine bindVars");

   my ($sql,$cursor,$sql_text,$text,$link,$infotext,$child_address,$foo);

   $dbh->{LongReadLen} = 10240;
   $dbh->{LongTruncOk} = 1;

   $sql = "
Select 
   sql_fulltext
from v\$sqlarea
   where sql_id = '$object_name'
";

   logit($sql);

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $sql_text = $cursor->fetchrow_array;
   $cursor->finish;

   logit("SQL statement: $sql_text");

   message("Bind variables for SQL statement <br> $sql_text");

   $sql = "
Select 
   distinct(child_address), child_number
from v\$sql_bind_capture
   where sql_id = '$object_name'
order by child_number
";

   logit($sql);

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   while (($child_address,$foo) = $cursor->fetchrow_array) {
      $sql = "
Select 
   child_number		\"Child #\",
   name			\"Name\",
   position		\"Position\",
   datatype_string	\"Datatype\",
   value_string		\"Value\"
from v\$sql_bind_capture
   where sql_id = '$object_name'
   and child_address = '$child_address'
   order by position
";

      logit($sql);

      $link = "";
      $infotext = "The SQL selected does not use bind variables.";
      DisplayTable($sql,$text,$link,$infotext);
   }
      
   $cursor->finish;

   logit("Exit subroutine bindVars");

}

sub quickExplain {

   logit("Enter subroutine quickExplain");

   my ($sql,$cursor,$explain);
   my ($sql_id,$sql_child_number);

   $sql_id		= $query->param('sql_id');
   $sql_child_number	= $query->param('sql_child_number');

   logit("   SQL_ID is $sql_id SQL_CHILD_NUMBER is $sql_child_number");

   $sql = "
Select * from table(DBMS_XPLAN.DISPLAY_CURSOR(('$sql_id'),$sql_child_number))
";

   logit("   $sql");

   $cursor = $dbh->prepare($sql);
   $cursor->execute;

   print <<"EOF";
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TR>
          <TD BGCOLOR='$cellcolor'>
            <PRE>
EOF
   while ($_ = $cursor->fetchrow_array) {
      logit("Explain: $_");
      print "$_";
   }
   print <<"EOF";
            </PRE>
          </TD>
        </TR>
     </TABLE>
    </TD>
  </TR>
</TABLE>
EOF
   
   logit("Exit subroutine quickExplain");

}

sub ASMdisks {

   logit("Enter subroutine ASMdisks");

   my ($sql,$cursor,$groupnum,$text,$link,$infotext);

   logit("   Looking for disks that are part of the $object_name diskgroup");

   $sql = "
Select group_number from v\$asm_diskgroup where name = '$object_name'
";
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $groupnum = $cursor->fetchrow_array;
   $cursor->finish;

   logit("   Group number for group $object_name is $groupnum");

   $sql = "
Select 
   name						\"Disk name\",
   path						\"Path\",
   mount_status					\"Mount status\",
   mode_status					\"Mode status\",
   state					\"State\",
   redundancy					\"Redundancy\",
   library					\"Library\",
   to_char(total_mb,'999,999,999,999,999')	\"Size (MB)\",
   to_char(free_mb,'999,999,999,999,999')	\"Free (MB)\",
   to_char(100-(free_mb*100/total_mb),'999.99')	\"Percent used\"
   
from v\$asm_disk
   where group_number = $groupnum
   order by disk_number
";

   $text = "ASM disks for group $object_name";
   #$link = "$scriptname?database=$database&object_type=ASMDISKS";
   $link = "";
   $infotext = "";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine ASMdisks");

}

sub datapumpJobs {

   logit("Enter subroutine datapumpJobs");

   my ($sql,$text,$link,$infotext,$refreshrate);

   $refreshrate = 5;

   print <<"EOF";
  <FORM METHOD="POST" ACTION="$scriptname">
    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
    <INPUT TYPE=HIDDEN NAME=database    VALUE=$database>
    <INPUT TYPE=HIDDEN NAME=object_type VALUE=$object_type>
    <INPUT TYPE=HIDDEN NAME=arg         VALUE=$object_name>
    <INPUT TYPE=HIDDEN NAME=refreshrate VALUE=$refreshrate>
    <INPUT TYPE=SUBMIT NAME=foobar      VALUE=\"AutoRefresh ($refreshrate)\">
  </FORM>
  <P>
EOF

   # Get toplevel info about the jobs
   $sql = "
Select
   vdj.job_id					\"Job ID\",
   ddj.job_name					\"Job name\",
   ddj.owner_name					\"Owner\",
   ddj.operation					\"Operation\",
   ddj.job_mode					\"Job mode\",
   ddj.state					\"State\",
   ddj.degree					\"Degree\",
   ddj.attached_sessions				\"Attached sessions\",
   ddj.datapump_sessions				\"Datapump sessions\"
from dba_datapump_jobs ddj, v\$datapump_job vdj
   where ddj.job_name = vdj.job_name
   and ddj.owner_name = vdj.owner_name
";

   $text = "Current datapump job(s)";
   $link = "$scriptname?database=$database&object_type=DATAPUMPJOB";
   $infotext = "No datapump jobs at this time";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine datapumpJobs");

}

sub flashbackInfo {

   logit("Enter subroutine flashbackInfo");

   my ($sql,$text,$link,$infotext,$refreshrate);
   my ($target,$days,$minutes,$hours,$remainder);
   my $message = "";

   $sql = "
Select
   name											\"Area\",
   to_char(space_limit, '999,999,999,999,999,999')					\"Space Limit\",
   round((space_used - space_reclaimable)/space_limit * 100, 1)				\"Percent Full\",
   to_char(space_limit - space_used + space_reclaimable,'999,999,999,999,999,999')	\"Space Available\",
   to_char(space_used,'999,999,999,999,999,999')					\"Space In Use\"
from v\$recovery_file_dest
";

   $text = "Flash recovery area summary";
   $link = "";
   $infotext = "";
   DisplayTable($sql,$text,$link,$infotext);

   # (Select to_char(estimated_flashback_size,'999,999,999,999,999,999') from v\$flashback_database_log)			\"Oracle Estimated Need\",

   $sql = "
Select
   file_type						\"File Type\",
   percent_space_used					\"Percent Full\",
   percent_space_reclaimable				\"Percent Reclaimable\",
   number_of_files					\"Number of Files\"
from v\$flash_recovery_area_usage";
   $text = "Flash recovery area detail";
   $link = "";
   $infotext = "";
   DisplayTable($sql,$text,$link,$infotext);

   # Find out what our retention period is set to, and how far we can flash back to.
   $sql = "Select retention_target from v\$flashback_database_log";
   my $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $target = $cursor->fetchrow_array;
   $cursor->finish;
   # Change minutes to hours or days / hours / minutes
   # Is it a day or more?
   if ($target >= 1440) {
      # It's at least a day
      $days = int($target / 1440);
      $remainder = $target % 1440;
      $target = $remainder;
      $message = "$days day(s) ,";
   }
   # Is it an hour or more?
   if ($target >= 60) {
      $hours = int($target / 60);
      $remainder = $target % 60;
      $target = $remainder;
      $message = "$message $hours hour(s), ";
   }
   $message = "$message $target minute(s)";
   #text("$message");

   $sql = "
Select
   to_char(oldest_flashback_time,'$nls_date_format')		\"Oldest Date / Time\",
   oldest_flashback_scn			\"Oldest SCN\",
   (Select '$message' from dual)	\"Retention Target\",
   to_char(flashback_size,'999,999,999,999,999,999')			\"Flashback Log Space Used\",
   to_char(estimated_flashback_size,'999,999,999,999,999,999')		\"Estimated Size Needed\"
from v\$flashback_database_log";

   $text = "Flashback log detail - This falls under the file type FLASHBACK LOG displayed above.";
   $link = "";
   $infotext = "";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine flashbackInfo");
}

sub datapumpJob {

   my ($sql,$sql1,$sql2,$cursor,$cursor1,$cursor2);
   my ($saddr,$session_type,$sid,$serial);
   my ($start_time,$last_update_time,$message);
   my ($owner_name,$job_name,$refreshrate);
   my ($text,$link,$infotext,$numrows);
   my ($target,$sofar,$total,$units,$start,$last,$remaining,$type);

# Completed object count
# Select count(*) from master_table where PROCESSING_STATE='W';
# Current object
# Select object_name, object_type, object_schema from master_table where in_progress is not null


   refreshButton();

#   print <<"EOF";
#  <FORM METHOD="POST" ACTION="$scriptname">
#    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
#    <INPUT TYPE=HIDDEN NAME=database    VALUE='$database'>
#    <INPUT TYPE=HIDDEN NAME=object_type VALUE='$object_type'>
#    <INPUT TYPE=HIDDEN NAME=arg VALUE='$object_name'>
#    <INPUT TYPE=HIDDEN NAME=refreshrate VALUE='$refreshrate'>
#    <INPUT TYPE=SUBMIT NAME=foobar      VALUE=\"AutoRefresh ($refreshrate)\">
#  </FORM>
#  <P>
#EOF

   $sql = "
Select job_name, owner_name from v\$datapump_job where job_id = '$object_name'
";
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   ($job_name,$owner_name) = $cursor->fetchrow_array;
   $cursor->finish;

   logit(" Job name is $job_name, Owner name is $owner_name for job ID $object_name");

   $sql2 = "
Select
   job_name					\"Job name\",
   owner_name					\"Owner\",
   operation					\"Operation\",
   job_mode					\"Job mode\",
   state					\"State\",
   degree					\"Degree\",
   attached_sessions				\"Attached sessions\",
   datapump_sessions				\"Datapump sessions\"
from dba_datapump_jobs
   where job_name = '$job_name'
   and owner_name = '$owner_name'
";

   $text = "";
   $link = "";
   $infotext = "The job is no longer active";
   $numrows = DisplayTable($sql2,$text,$link,$infotext);

   $sql2 = "
Select 
   to_char(count(*),'999,999,999,999,999')	\"Objects completed\"
 from $owner_name.$job_name where PROCESSING_STATE='W'
";

   $text = "";
   $link = "";
   $infotext = "";
   $numrows = DisplayTable($sql2,$text,$link,$infotext);

   $sql2 = "
Select 
   object_type					\"Object type\", 
   object_schema				\"Schema\",
   object_name					\"Object name\" 
from $owner_name.$job_name where in_progress is not null
";

   $text = "Current object(s) in progress";
   $link = "";
   $infotext = "No information available on current object";
   $numrows = DisplayTable($sql2,$text,$link,$infotext);

   $sql = "
   Select sid, serial#, saddr from v\$session where saddr in 
      (Select saddr from v\$datapump_session where job_id = 
      (Select job_id from v\$datapump_job where job_name = '$job_name' and owner_name = '$owner_name'))
";

   $cursor = $dbh->prepare($sql);
   logit("Error: $DBI::errstr");
   $cursor->execute;
   logit("Error: $DBI::errstr");

   message("Not all sessions will have long operation information to display.");
   # Start printing the table
   print "<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>\n";
   print "<TR><TD WIDTH=100%>\n";
   print "<TABLE BORDER=0 cellpadding=2 cellspacing=1>\n";
   print "  <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Type</TH>\n";
   print "  <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Target</TH>\n";
   print "  <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>SID</TH>\n";
   print "  <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Serial#</TH>\n";
   print "  <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>So far</TH>\n";
   print "  <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Total</TH>\n";
   print "  <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Remaining</TH>\n";
   print "  <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Units</TH>\n";
   print "  <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Start time</TH>\n";
   print "  <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Last update</TH>\n";
   print "  <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Message</TH>\n";

   while (($sid,$serial,$saddr) = $cursor->fetchrow_array) {
      $sql1 = "
Select
   TARGET_DESC							\"Target\",
   SOFAR							\"So far\",
   TOTALWORK							\"Total\",
   UNITS							\"Units\",
   TO_CHAR(START_TIME,'Month DD, YYYY - HH24:MI:SS')		\"Start time\",
   TO_CHAR(LAST_UPDATE_TIME,'Month DD, YYYY - HH24:MI:SS')	\"Last update\",
   TIME_REMAINING						\"Remaining\",
   MESSAGE							\"Message\"
from v\$session_longops 
where sid = $sid and serial# = $serial
";
      $sql2 = "
Select session_type from dba_datapump_sessions
   where saddr = '$saddr'
";
      $cursor2 = $dbh->prepare($sql2);
      logit("Error: $DBI::errstr");
      $cursor2->execute;
      logit("Error: $DBI::errstr");
      $type = $cursor2->fetchrow_array;
      $cursor2->finish;

      logit("   SID = $sid SERIAL = $serial SADDR = $saddr TYPE = $type"); 
#      while (@row = $cursor->fetchrow_array) {
#         $count++;
#         print "<TR ALIGN=LEFT>";
#         print "<TD VALIGN=TOP BGCOLOR='$cellcolor'";
#         print "><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$row[$field]</TD>\n";
#         print "</TR>\n";
#      }
#      print "</TABLE></TD></TR>\n";
#      print "</TABLE>\n";


      $cursor1 = $dbh->prepare($sql1);
      $cursor1->execute;
      ($target,$sofar,$total,$units,$start,$last,$remaining,$message) = $cursor1->fetchrow_array;
      print "<TR ALIGN=LEFT>\n";
      print "  <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$type</TD>\n";
      print "  <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$target</TD>\n";
      print "  <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$sid</TD>\n";
      print "  <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$serial</TD>\n";
      print "  <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$sofar</TD>\n";
      print "  <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$total</TD>\n";
      print "  <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$remaining</TD>\n";
      print "  <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$units</TD>\n";
      print "  <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$start</TD>\n";
      print "  <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$last</TD>\n";
      print "  <TD VALIGN=TOP BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$message</TD>\n";
      print "</TR>\n";
      logit("$type,$target,$sid,$serial,$sofar,$total,$units,$start,$last,$remaining,$message");
      $cursor1->finish;
   }
   $cursor->finish;
   print "</TABLE></TD></TR></TABLE>\n";
 
}

sub showDBfiles {

   logit("Enter subroutine showDBfiles");

   my ($sql,$text,$link,$infotext);

print <<"EOF";
<TABLE BORDER=0 CELLPADDING=0 CELLSPACING=0>
  <TR>
    <TD ALIGMN=CENTER>
      <FORM METHOD="GET" ACTION="$scriptname">
        <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
        <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
        <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="FILEGRAPH">
        <INPUT TYPE="SUBMIT" NAME="filegraph" VALUE="Datafile graph by file I/O">
      </FORM>
    </TD>
  </TR>
</TABLE>
EOF

# Show any files that need media recovery.

   $sql = "$copyright
SELECT 
   A.FILE_NAME					\"File name\",
   A.TABLESPACE_NAME				\"Tablespace name\",
   A.FILE_ID					\"File#\",
   A.STATUS					\"Status\",
   B.ERROR					\"Error\",
   B.CHANGE#					\"Start SCN\",
   TO_CHAR(B.TIME,'Month DD, YYYY - HH24:MI:SS')	\"Recover from..\"
FROM DBA_DATA_FILES A,
     V\$RECOVER_FILE B
WHERE A.FILE_ID = B.FILE#
";

   $text = "Datafiles need recovery!!";
   $link = "$scriptname?database=$database&object_type=DATAFILE";
   $infotext = "No datafiles are needing media recovery :-)";
   DisplayTable($sql,$text,$link,$infotext);

   $sql = "$copyright
SELECT
   TO_CHAR(SUM(BYTES),'999,999,999,999,999')    \"Total allocated space\"
FROM DBA_DATA_FILES
";

   $text = "";
   $link = "";
   DisplayTable($sql,$text,$link);

   dbFileList();

   logit("Exit subroutine showDBfiles");

}

sub dbFileList {

# General datafile information, all datafiles

   my ($sql,$text,$link,$infotext);

   $sql = "$copyright
SELECT
   A.FILE_NAME					\"File name\",
   TO_CHAR(A.BYTES,'999,999,999,999')		\"Bytes\",
   A.TABLESPACE_NAME				\"Tablespace_name\",
   TO_CHAR(B.PHYBLKRD,'999,999,999,999')	\"Physical block reads\",
   TO_CHAR(B.PHYBLKWRT,'999,999,999,999')	\"Physical block writes\",
   A.STATUS					\"Status\"
FROM DBA_DATA_FILES A, V\$FILESTAT B
   WHERE A.FILE_ID = B.FILE#
ORDER BY A.FILE_NAME, A.TABLESPACE_NAME
";

   $sql = "$copyright
SELECT
   A.FILE_NAME					\"File name\",
   TO_CHAR(A.BYTES,'999,999,999,999')		\"Bytes\",
   A.TABLESPACE_NAME				\"Tablespace_name\",
   TO_CHAR(B.PHYBLKRD,'999,999,999,999')	\"Physical block reads\",
   TO_CHAR(B.PHYBLKWRT,'999,999,999,999')	\"Physical block writes\",
   A.STATUS					\"Status\",
   DECODE(A.AUTOEXTENSIBLE,
                           'YES','Yes',
                           'NO','No')		\"Xtend?\",
   TO_CHAR(A.MAXBYTES,'999,999,999,999')	\"Max bytes\",
   TO_CHAR(A.INCREMENT_BY*$db_block_size,'999,999,999,999')	\"Increment\"
FROM DBA_DATA_FILES A, V\$FILESTAT B
   WHERE A.FILE_ID = B.FILE#
ORDER BY A.FILE_NAME, A.TABLESPACE_NAME
" if ($notoracle7);

   $dbh->do("Alter session set optimizer_mode=RULE");

   $sql = "$copyright
SELECT
   A.FILE_NAME					\"File name\",
   TO_CHAR(A.BYTES,'999,999,999,999,999')		\"Bytes\",
   A.TABLESPACE_NAME				\"Tablespace name\",
   TO_CHAR(B.PHYBLKRD,'999,999,999,999,999')	\"Physical block reads\",
   TO_CHAR(B.PHYBLKWRT,'999,999,999,999,999')	\"Physical block writes\",
   A.STATUS					\"Status\",
   DECODE(A.AUTOEXTENSIBLE,
                           'YES','Yes',
                           'NO','No')		\"Xtend?\",
   TO_CHAR(A.MAXBYTES,'999,999,999,999,999')	\"Max bytes\",
   TO_CHAR(A.INCREMENT_BY*$db_block_size,'999,999,999,999,999')	\"Increment\"
FROM DBA_DATA_FILES A, V\$FILESTAT B
   WHERE A.FILE_ID = B.FILE#
UNION
SELECT
   A.FILE_NAME					\"File name\",
   TO_CHAR(A.BYTES,'999,999,999,999,999')		\"Bytes\",
   A.TABLESPACE_NAME				\"Tablespace name\",
   TO_CHAR(B.PHYBLKRD,'999,999,999,999,999')	\"Physical block reads\",
   TO_CHAR(B.PHYBLKWRT,'999,999,999,999,999')	\"Physical block writes\",
   A.STATUS					\"Status\",
   DECODE(A.AUTOEXTENSIBLE,
                           'YES','Yes',
                           'NO','No')		\"Xtend?\",
   TO_CHAR(A.MAXBYTES,'999,999,999,999,999')	\"Max bytes\",
   TO_CHAR(A.INCREMENT_BY*$db_block_size,'999,999,999,999,999')	\"Increment\"
FROM DBA_TEMP_FILES A, V\$TEMPSTAT B
   WHERE A.FILE_ID = B.FILE#
ORDER BY \"File name\", \"Tablespace name\"
" if ($oraclei);

   $text = "Datafile information" unless $norefreshbutton;
   $link = "$scriptname?database=$database&object_type=DATAFILE";
   DisplayTable($sql,$text,$link);

}

sub EnterPasswd {

   logit("Enter subroutine EnterPasswd");

# Usage: EnterPasswd($database);

   if ($object_type ne "MENU") {

   my $database      = shift;

   my ($title,$heading);

   $title	= "Add database $database";
   $heading	= "Please enter a username and password for database $database.<BR>This user needs to have CREATE SESSION and either SELECT ANY TABLE privileges, or privileges to see all of the neccessary data dictionary tables.";

   Header($title,$heading,$font,$fontsize,$fontcolor,$bgcolor);

   print <<"EOF";
</CENTER>
  <P>
    <TABLE BGCOLOR="BLACK" WIDTH="400" CELLPADDING="1" CELLSPACING="0" BORDER="0">
      <TR>
        <TD VALIGN="TOP">
          <TABLE BGCOLOR="$cellcolor" WIDTH="100%" CELLPADDING="2" CELLSPACING="1" BORDER="0">
            <TR ALIGN="CENTER">
              <TD ALIGN=LEFT>
                <FORM METHOD="POST" ACTION="$scriptname">
                <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
                <BR><STRONG>&nbsp;&nbsp;&nbsp;Enter the username</STRONG>
                <P>
                <INPUT TYPE="TEXT" SIZE="20" NAME="username" MAXLENGTH="20">
                <P>
                <STRONG>&nbsp;&nbsp;&nbsp;Enter the password</STRONG>
                <P>
                <INPUT TYPE="PASSWORD" SIZE="20" NAME="password" MAXLENGTH="20">
                <P>
                <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="ADDPASSWORD">
                <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
                &nbsp;&nbsp;&nbsp;<INPUT TYPE="SUBMIT" VALUE="Submit">
                </FORM>
              </TD>
            </TR>
          </TABLE>
        </TD>
      </TR>
    </TABLE>
EOF
   logit("Exit subroutine EnterPasswd");
exit;
    } else {
      Header($title,$heading,$font,$fontsize,$fontcolor,$bgcolor);
   }
   logit("Exit subroutine EnterPasswd");
}

sub GetPasswd {

   logit("Enter subroutine GetPasswd");

# Usage: $info = GetPasswd($database);

   my $database      = shift;
   my ($sessionid,$username,$password,$usercookie,$passcookie,$info,$message,$duration,$url,$path);
   my ($sessioncookie,$sessioncookie1,$sessioncookie2,$bgline,$mydatabase);

   if ( defined $myoracletoolexpire ) {
      $path = dirname($scriptname);
      logit("   Expiring myOracletool cookie");
      $sessioncookie1 = cookie(-name=>"MyOracletool",-value=>"undefined",-expires=>"-1y");
      logit("   Sessioncookie1 is $sessioncookie1, Error for sessioncookie1 is $!");
      $sessioncookie2 = cookie(-name=>"MyOracletoolDB",-value=>"undefined",-expires=>"-1y");
      logit("   Sessioncookie2 is $sessioncookie2, Error for sessioncookie2 is $!");
      print header(-cookie=>$sessioncookie1,-cookie=>$sessioncookie2);
      logit(" Error for header is $!");
      $message     = "Connection info for MyOracletool has been removed.";
      $duration    = "1";
      $url         = "$scriptname?object_type=MYORACLETOOL&database=$database";

      $bgline = "<BODY BGCOLOR=$bgcolor>\n";

      if ($bgimage) {
         if ((-e "$ENV{'DOCUMENT_ROOT'}/$bgimage") && (-r "$ENV{'DOCUMENT_ROOT'}/$bgimage")) {
            logit("   Background image is $ENV{'DOCUMENT_ROOT'}/$bgimage and is readable");
            $bgline = "<BODY BACKGROUND=$bgimage>\n";
         }
      }
   }


   if ( defined $expire ) {
      logit("   Expiring password cookie");
      $path = dirname($scriptname);
      $sessionid = "undefined";
      $sessioncookie = cookie(-name=>"$database.sessionid",-value=>"$sessionid",-expires=>"-1y");
      print header(-cookie=>$sessioncookie);
      $message     = "Password cookie for database $database has been expired.";
      $duration    = "1";
      $url         = "$scriptname";

      $bgline = "<BODY BGCOLOR=$bgcolor>\n";

      if ($bgimage) {
         if ((-e "$ENV{'DOCUMENT_ROOT'}/$bgimage") && (-r "$ENV{'DOCUMENT_ROOT'}/$bgimage")) {
            logit("   Background image is $ENV{'DOCUMENT_ROOT'}/$bgimage and is readable");
            $bgline = "<BODY BACKGROUND=$bgimage>\n";
         }
      }
   }

   if ( $myoracletoolexpire || $expire ) {

      print <<"EOF";
<HTML>
  <HEAD>
    <TITLE>Notice!</TITLE>
    <META HTTP-EQUIV="Refresh" Content="$duration;URL=$url">
  </HEAD>
    $bgline
    <FONT FACE="$font" SIZE="$fontsize" COLOR="$fontcolor">
    <CENTER>
      $message
    </CENTER
  </BODY
</HTML>
EOF

      logit("Exit subroutine GetPasswd");
      Footer();
   }

   $sessionid = cookie("$database.sessionid");
#   print header(-cookie=>$sessioncookie);

   ($username,$password) = decodeSessionid($sessionid);
   $info = "$username $password";
   logit("Exit subroutine GetPasswd");
   return($info);


}

sub encryptionEnabled {

   logit("Enter sub encryptionEnabled");

   my $digest_found	= (eval "require Digest::MD5");
   my $crypt_found	= (eval "require Crypt::CBC");
   my $idea_found	= (eval "require Crypt::IDEA");
   my $blowfish_found	= (eval "require Crypt::Blowfish");
   my $mime_found	= (eval "require MIME::Base64");

# We need Digest::MD5 for any type of encryption, so check for 
# this first.
   if ($digest_found) {
      logit("   Digest::MD5 is installed. Good");

# Check for Crypt::CBC. If found, check for encryption methods.
# If Crypt::CBC and an encryption method are found, we can enable
# encryption level 2.

      if ($crypt_found) {
         logit("   Crypt::CBC is installed. Good.");
         logit("   Encryption method is $encryption_method.");
         if ($encryption_method eq "IDEA") {
            logit("   Checking for Crypt::IDEA");
            if ($idea_found) {
               logit("      Crypt::IDEA is installed. Good.");
               $encryption_enabled = 2;
            } else {
               logit("      Crypt::IDEA is not installed!");
            }
         }
         if ($encryption_method eq "BLOWFISH") {
            $encryption_method = "Blowfish";
            logit("   Checking for Crypt::Blowfish");
            if ($blowfish_found) {
               logit("      Crypt::Blowfish is installed. Good.");
               $encryption_enabled = 2;
            } else {
               logit("      Crypt::Blowfish is not installed!");
            }
         }
      } else {
         logit("   Crypt::CBC is not installed!");
         logit("   Encryption level 2 is not possible.");
         logit("   Checking for MIME::Base64 instead.");
         if ($mime_found) {
            logit("   MIME::Base64 is installed. Good.");
            $encryption_enabled = 1;
         }
      }
   } else {
      logit("   Digest::MD5 is not installed. Encryption disabled!");
   }
   logit("   Value for encryption_enabled is $encryption_enabled");

   if ($encryption_enabled) {
      if ($encryption_string eq "changeme") {
         logit("   Encryption key is set to the default! Change it!");
       } else {
         logit("   Encryption key is non-default. Good.");
      }
   }
   logit("Exit sub encryptionEnabled");
}

sub buildSessionid {
   logit("Enter sub buildSessionid");
   my ($username,$password) = @_;
   
   my $sessionid;

# $encryption enabled will be 0 if no encryption modules are installed.
# $encryption enabled will be 1 if Digest::MD5 is installed,
# but Crypt::CBC _and_ CRYPT::IDEA are not.
# $encryption enabled will be 3 if all three modules are installed.

   if ($encryption_enabled) {
      logit("   Encryption enabled, attempting to encrypt username / password.");
      if ($encryption_enabled == 1) {
         logit("   Digest::MD5 encryption only.");
         $sessionid = encodeLevel1($username,$password);
      }
      if ($encryption_enabled == 2) {
         logit("   Full IDEA encryption.");
         $sessionid = encodeLevel2($username,$password);
      }
      if ($sessionid) {
         logit("   Encrypt was successful.");
       } else {
         logit("   Encrypt was not successful!");
      }
    } else {
      logit("   Encryption not enabled, attempting to build unencrypted sessionid.");
      ($sessionid) = "$username~$password";
      if ($sessionid) {
         logit("   Build was successful.");
       } else {
         logit("   Build was not successful!");
      }
   }
   logit("Exit sub buildSessionid");
   return($sessionid);
}

sub encodeLevel1 {

   logit("Enter sub encodeLevel1");

   my ($username,$password) = @_;
   my ($sessionid,$context,$checksum);

   $context = Digest::MD5->new;
      logit("   New MD5 context created.");
   $context->add($username,$password,$encryption_string);
      logit("   Username / password added to context.");
   $checksum = $context->digest();
      logit("   Checsum generated.");
   $sessionid=join("-",
      map { MIME::Base64::encode($_) }
      ($username,$password,$checksum));
   $sessionid=~s|\n||g;

   return($sessionid);

   logit("Exit sub encodeLevel1");

}

sub encodeLevel2 {

   logit("Enter sub encodeLevel2");

   my ($username,$password) = @_;
   my $sessionid;

   $sessionid = Crypt::CBC->new($encryption_string,$encryption_method)->
   encrypt_hex(join("\0",($username,$password)));

   logit("Exit sub encodeLevel2");

   return($sessionid);

   
}

sub decodeLevel1 {

   logit("Enter sub decodeLevel1");

   my $sessionid = shift or return;
   my ($username,$password,$context,$checksum,$new_checksum);

   ($username,$password,$checksum) =
      map { MIME::Base64::decode($_) } split(/-/,$sessionid);
   $context = Digest::MD5->new;
   $context->add($username,$password,$encryption_string);
   $new_checksum = $context->digest();
   if ( $checksum ne $new_checksum ) { 
      logit("   WARNING: The encryption string has been tampered with or changed.");
      $username = "$new_checksum";
      $password = "$new_checksum";
   }

   logit("Exit sub decodeLevel1");

   return ($username,$password);

}

sub decodeLevel2 {

   logit("Enter sub decodeLevel2");
   logit("   Encryption method is $encryption_method");

   my $sessionid = shift or return;
   my ($username,$password);

   ($username,$password) = split(/\0/, Crypt::CBC->new($encryption_string,$encryption_method)->
   decrypt_hex($sessionid));

   return($username,$password); 

   logit("Exit sub decodeLevel2");

}

sub decodeSessionid {
   logit("Enter sub decodeSessionid");
   my($sessionid) = shift;
   my ($username,$password);
   if ($encryption_enabled) {   
      if ($encryption_enabled == 1) {
         logit("   Encryption enabled (1), attempting to decrypt username / password.");
         ($username,$password) = decodeLevel1($sessionid);
      }
      if ($encryption_enabled == 2) {
         logit("   Encryption enabled(2), attempting to decrypt username / password.");
         ($username,$password) = decodeLevel2($sessionid);
      }
      if ($username && $password) {
         logit("   Decrypt was successful.");
       } else {
         logit("   Decrypt was not successful!");
      }
    } else {
      logit("   Encryption not enabled, attempting to split username / password.");
      ($username,$password) = split(/~/, $sessionid);
      if ($username && $password) {
         logit("   Split was successful.");
       } else {
         logit("   Split was not successful!");
      }
   }
   logit("Exit sub decodeSessionid");
   return ($username,$password);
}

sub addPasswd {

   logit("Enter subroutine addPasswd");

   my $database		= shift;
   my $username		= shift;
   my $password		= shift;

   my ($sql,$cursor,$count,$message,$duration,$url,$usercookie,$passcookie);
   my ($role,@allroles,$foo,$dbstatus,$sessionid,$sessioncookie,$bgline);

# Connect to the database.

   $dbh = dbConnect($database,$username,$password);

# Determine the database status. (OPEN,MOUNTED etc.)

   $dbstatus = dbStatus();

#   if ($dbstatus eq "OPEN") {

# First, check to be sure this user has "SELECT ANY TABLE" privilege.
# If not, send them packing.

# Actually, let's not do this anymore.. The ORACLETOOL role replaces this..

#      $count = checkPriv("SELECT ANY TABLE");

#      if ($count < 1) {
#         ErrorPage("The username you have specified does not have the appropriate permissions to use this tool. Please specify a username with SELECT ANY TABLE privileges.");
#      }
#      $dbh->disconnect;
#   }

   logit("   Updating password for database $database");
   $foo = dirname($scriptname);

   if ($encryption_enabled) {
      $sessionid = buildSessionid($username,$password);
      logit("   SessionID = $sessionid");
      logit("   Encryption is enabled.");
    } else {
      $sessionid = "$username~$password";
      logit("   Encryption is NOT enabled.");
   }

   logit("   Building cookie");
   logit("      Name: $database.sessionid");
   logit("      Value: $sessionid");
   logit("      Expires: $expiration");
   $sessioncookie = cookie(-name=>"$database.sessionid",-value=>"$sessionid",-expires=>"$expiration");
   if ($!) {
      logit("      Error: $!");
   }
   print header(-cookie=>$sessioncookie);
   if ($!) {
      logit("      Error: $!");
   }

   $message     = "Password for database $database has been updated.";
   $duration    = "1";
   $url         = "$scriptname?database=$database&object_type=FRAMEPAGE";

   $bgline = "<BODY BGCOLOR=$bgcolor>\n";

   if ($bgimage) {
      if ((-e "$ENV{'DOCUMENT_ROOT'}/$bgimage") && (-r "$ENV{'DOCUMENT_ROOT'}/$bgimage")) {
         logit("   Background image is $ENV{'DOCUMENT_ROOT'}/$bgimage and is readable");
         $bgline = "<BODY BACKGROUND=$bgimage>\n";
      }
   }
   
   print <<"EOF";
<HTML>
  <HEAD>
    <TITLE>Notice!</TITLE>
    <META HTTP-EQUIV="Refresh" Content="$duration;URL=$url">
  </HEAD>
    $bgline
    <FONT FACE="$font" SIZE="$fontsize" COLOR="$fontcolor">
    <CENTER>
      $message
    </CENTER
  </BODY
</HTML>
EOF

logit("Exit subroutine addPasswd");

exit;
}

sub recentEvents {

   logit("Enter subroutine recentEvents");

   my ($sql,$text,$link,$infotext,$cols);

   refreshButton();

   $sql = "$copyright
SELECT 
   TO_CHAR(TO_DATE(D.VALUE,'J'),'Day, Month DD, YYYY')||' -  '||
   TO_CHAR(TO_DATE(S.VALUE,'sssss'),'HH24:MI:SS')		\"Instance startup time\"
FROM V\$INSTANCE D, V\$INSTANCE S
   WHERE D.KEY = 'STARTUP TIME - JULIAN'
   AND S.key = 'STARTUP TIME - SECONDS'
" if ($oracle7);

   $sql = "$copyright
SELECT
   TO_CHAR(STARTUP_TIME,'Day, Month DD YYYY -  HH24:MI:SS')	\"Instance startup time\"
FROM V\$INSTANCE
" if ($oracle8);

   $text = "";
   $link = "";
   DisplayTable($sql,$text,$link);

   $sql = "$copyright
SELECT 
   TO_CHAR(COUNT(*),'999,999,999,999')	\"Log switches\"
FROM V\$LOG_HISTORY
   WHERE FIRST_TIME > SYSDATE-1
";

   $text = "Number of redo log switches last 24 hours.";
   $link = "";
   DisplayTable($sql,$text,$link);

   $sql = "$copyright
SELECT
   NAME				\"Username\"
FROM SYS.USER\$
   WHERE CTIME > SYSDATE-30
   AND TYPE = 1
";

   $sql = "$copyright
SELECT
   NAME				\"Username\"
FROM SYS.USER\$
   WHERE CTIME > SYSDATE-30
   AND TYPE# = 1
" if (! $oracle7);

   $text        = "Users added in the last 30 days.";
   $link        = "$scriptname?database=$database&object_type=USERINFO";
   $infotext    = "No users have been added in the last 30 days.";

   DisplayColTable($sql,$text,$link,$infotext,$schema_cols);

   $sql = "$copyright
SELECT
   NAME						\"Role\"
FROM SYS.USER\$
   WHERE CTIME > SYSDATE-30
   AND TYPE = 0
";

   $sql = "$copyright
SELECT
   NAME						\"Role\"
FROM SYS.USER\$
   WHERE CTIME > SYSDATE-30
   AND TYPE# = 0
" if (! $oracle7);

   $text        = "Roles added in the last 30 days.";
   $link        = "$scriptname?database=$database&object_type=ROLES";
   $infotext    = "No roles have been added in the last 30 days.";

   DisplayColTable($sql,$text,$link,$infotext,$schema_cols);

   if (! $oracle7) {
     $sql = "$copyright
SELECT
   VDF.NAME							\"File name\",
   TO_CHAR(VDF.BYTES,'999,999,999,999')				\"Bytes\",
   TO_CHAR(VDF.CREATION_TIME,'Dy, Mon DD YYYY HH24:MI:SS')	\"Creation date\",
   TS.NAME							\"Tablespace name\"
FROM V\$DATAFILE VDF,
     SYS.TS\$ TS
WHERE VDF.CREATION_TIME > SYSDATE - 30
AND VDF.TS# = TS.TS#
   ORDER BY VDF.CREATION_TIME DESC
";

      $text = "Datafiles which have been added in the last 30 days.";
      $infotext = "There have been no datafiles added in the last 30 days.";
      $link = "";
      DisplayTable($sql,$text,$link,$infotext);
   }

   $sql = "$copyright
SELECT
   DS.SEGMENT_NAME						\"Object name\",
   DS.SEGMENT_TYPE						\"Object type\",
   DS.OWNER							\"Owner\",
   DO.STATUS							\"Status\",
   DS.TABLESPACE_NAME						\"Tablespace name\",
   TO_CHAR(DO.LAST_DDL_TIME,'Dy, Mon DD YYYY HH24:MI:SS')	\"Last DDL date\",
   TO_CHAR(DO.CREATED,'Dy, Mon DD YYYY HH24:MI:SS')		\"Creation date\"
FROM DBA_SEGMENTS DS, DBA_OBJECTS DO
   WHERE DS.SEGMENT_TYPE NOT LIKE '%PARTITION'
   AND DS.SEGMENT_NAME = DO.OBJECT_NAME
   AND DO.CREATED > SYSDATE-1
ORDER BY CREATED, SEGMENT_TYPE DESC
";

   $text = "Objects which have been created in the last 24 hours.";
   $infotext = "There have been no objects created in the last 24 hours.";
   ObjectTable($sql,$text,$infotext);

   $sql = "$copyright
SELECT
   DS.SEGMENT_NAME						\"Object name\",
   DS.SEGMENT_TYPE						\"Object type\",
   DS.OWNER							\"Owner\",
   DO.STATUS							\"Status\",
   DS.TABLESPACE_NAME						\"Tablespace name\",
   TO_CHAR(DO.LAST_DDL_TIME,'Dy, Mon DD YYYY HH24:MI:SS')	\"Last DDL date\",
   TO_CHAR(DO.CREATED,'Dy, Mon DD YYYY HH24:MI:SS')		\"Creation date\"
FROM DBA_SEGMENTS DS, DBA_OBJECTS DO
   WHERE DS.SEGMENT_TYPE NOT LIKE '%PARTITION'
   AND DS.SEGMENT_NAME = DO.OBJECT_NAME
   AND DO.LAST_DDL_TIME > SYSDATE-1
ORDER BY LAST_DDL_TIME DESC
";

   $text = "Objects which have been edited in the last 24 hours.";
   $infotext = "There have been no objects edited in the last 24 hours.";
   ObjectTable($sql,$text,$infotext);

   logit("Exit subroutine recentEvents");

}

sub showPerformance {

   logit("Enter subroutine showPerformance");

   my ($sql,$cursor,$value,$text,$link,$infotext);
   my ($username,$sid,$counter,$rows,$dbg,$cg,$pr);

   refreshButton();

# Check to see if TIMED_STATISTICS is set to true.

   $sql = "$copyright
SELECT VALUE
   FROM V\$PARAMETER 
WHERE NAME = 'timed_statistics'
";
   $cursor=$dbh->prepare($sql);
   $cursor->execute;
   $value = $cursor->fetchrow_array;
   $cursor->finish;
 
# If timed_statistics is enabled, get some info about CPU usage.
 
   if ($value eq "TRUE") {
      $sql = "$copyright
SELECT 
   SS.USERNAME				\"Username\", 
   SE.SID				\"SID\",
   TO_CHAR(VALUE,'999,999,999,999')	\"Value\"
FROM V\$SESSION SS,
     V\$SESSTAT SE,
     V\$STATNAME SN
WHERE SE.STATISTIC# = SN.STATISTIC#
   AND NAME = 'CPU used by this session'
   AND SE.SID = SS.SID
   AND SS.USERNAME IS NOT NULL
ORDER BY VALUE DESC
";

   $text	= "Top three CPU users (Via TIMED_STATISTICS)";
   $infotext	= "No CPU usage via Oracle at this time.";
   $link	= "";
   $rows	= 2;
   DisplayTable($sql,$text,$link,$infotext,$rows);
   } else {
      message("TIMED_STATISTICS is set to FALSE.");
   }

# Put SGA and memory info in a table together to save space..

   print <<"EOF";
<TABLE BORDER=0 CELLPADDING=20>
  <TR>
    <TD VALIGN=TOP ALIGN=CENTER>
    <FONT FACE="$font" SIZE="$fontsize" COLOR="$fontcolor">
EOF

# Instance SGA information

   $sql = "$copyright
SELECT
   NAME                                 \"Name\",
   TO_CHAR(VALUE,'999,999,999,999')     \"Value\"
FROM V\$SGA
";

   $text = "Instance SGA info";
   $link = "";
   DisplayTable($sql,$text,$link);

print <<"EOF";
    </TD>
    <TD VALIGN=TOP ALIGN=CENTER>
    <FONT FACE="$font" SIZE="$fontsize" COLOR="$fontcolor">
EOF

   $sql = "$copyright
SELECT
   NAME                                 \"Name\",
   TO_CHAR(BYTES,'999,999,999,999')     \"Bytes\"
FROM V\$SGASTAT
   WHERE NAME IN ('free memory','db_block_buffers','log_buffer','dictionary cache','sql area','library cache')
";

   $sql = "$copyright
SELECT
   NAME                                 \"Name\",
   NVL(POOL,'n/a')			\"Pool\",
   TO_CHAR(BYTES,'999,999,999,999')     \"Bytes\"
FROM V\$SGASTAT
   WHERE NAME IN ('free memory','db_block_buffers','log_buffer','dictionary cache','sql area','library cache')
" if ($notoracle7);

   $text = "Memory usage";
   $link = "";
   DisplayTable($sql,$text,$link);

   print <<"EOF";
    </TD>
  </TR>
  <TR>
    <TD VALIGN=TOP ALIGN=CENTER>
    <FONT FACE="$font" SIZE="$fontsize" COLOR="$fontcolor">
EOF

   $sql = "$copyright
SELECT
   VALUE 
FROM V\$SYSSTAT 
   WHERE NAME IN ('db block gets', 'consistent gets', 'physical reads')
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   ($dbg,$cg,$pr) = $cursor->fetchrow_array;
   $cg = $cursor->fetchrow_array;
   $pr = $cursor->fetchrow_array;
   $cursor->finish;

   logit("   $dbg,$cg,$pr");

   my $ratio = 1-($pr/($dbg+$cg));
   my $column;

   # Display in millions if it's greater than 500 million

   if ($dbg > 500000000) {
      $dbg = $dbg/1000000;
      $column = "DB block gets (millions)";
   } else {
      $column = "DB block gets";
   }

   $sql = "
SELECT 
   TO_CHAR($dbg,'999,999,999,999,999,999')	\"$column\",
   TO_CHAR($cg,'999,999,999,999,999')	\"Cons. gets\",
   TO_CHAR($pr,'999,999,999,999,999')	\"Phy. reads\",
   TO_CHAR($ratio*100,'999.99')||'%'		\"Ratio\"
 FROM DUAL
";

   $text = "DB buffer cache";
   $link = "";
   DisplayTable($sql,$text,$link);

print <<"EOF";
    </TD>
    <TD VALIGN=TOP ALIGN=CENTER>
    <FONT FACE="$font" SIZE="$fontsize" COLOR="$fontcolor">
EOF

# Data dictionary cache miss ratio

   $sql = "$copyright
SELECT
   TO_CHAR(SUM(gets),'999,999,999,999')                         \"Gets\",
   TO_CHAR(SUM(getmisses),'999,999,999,999')                    \"Misses\",
   TO_CHAR(SUM(getmisses) / SUM(gets) * 100,'999.99')||'%'         \"Percentage\"
FROM V\$ROWCACHE
";

   $text = "Data dictionary cache miss ratio";
   $link = "";
   DisplayTable($sql,$text,$link);

   print <<"EOF";
    </TD>
  </TR>
</TABLE>
EOF

# Library cache info

#   $sql = "$copyright
#SELECT
#   SUM(PINHITS-RELOADS)/SUM(PINS)	\"Hit ratio %\",
#   SUM(RELOADS)/SUM(PINS)		\"Reload %\"
#FROM V\$LIBRARYCACHE
#";

#   $text = "Library cache info";
#   $link = "";
#   DisplayTable($sql,$text,$link);

# Sort area information. Thanks to Tommy Wareing.

   $sql = "$copyright
SELECT
   S.SID				\"SID\",
   S.SERIAL#				\"Serial#\",
   S.USERNAME				\"Ora user\",
   S.OSUSER				\"OS user\",
   U.TABLESPACE				\"Tablespace\",
   SUM(U.EXTENTS)			\"Extents\",
   SUM(U.BLOCKS)			\"Blocks\",
   SA.SQL_TEXT				\"SQL Text\"
FROM V\$SESSION S,
     V\$SORT_USAGE U,
     V\$SQLAREA SA
WHERE S.SADDR=U.SESSION_ADDR
AND U.CONTENTS='TEMPORARY'
AND S.SQL_ADDRESS=SA.ADDRESS(+)
GROUP BY S.SID, S.SERIAL#, S.USERNAME, S.OSUSER, U.TABLESPACE, 
SA.SQL_TEXT
";

   $text = "Sort Area Usage";
   $link = "";
   $infotext = "No sorts currently using disk.";
   DisplayTable($sql,$text,$link,$infotext);

# Percentage of sorts that are taking place in memory,
# as opposed to in temporary segments on disk.

$sql = "$copyright
SELECT 
   ROUND((SUM(DECODE(NAME, 'sorts (memory)', VALUE, 0))
        / (SUM(DECODE(NAME, 'sorts (memory)', VALUE, 0))
        + SUM(DECODE(NAME, 'sorts (disk)', VALUE, 0))))
        * 100,2) \"Percentage\"
FROM V\$SYSSTAT
";

   $text = "Percentage of sorts that are taking place in memory";
   $link = "";
   DisplayTable($sql,$text,$link);


# Information from v$librarycache

   $sql = "$copyright
SELECT
   NAMESPACE                                            \"Namespace\",
   TO_CHAR(GETS,'999,999,999,999')                      \"Gets\",
   TO_CHAR(GETHITS,'999,999,999,999')                   \"Gethits\",
   TO_CHAR(GETHITRATIO,'99.99')                         \"GetHitRatio\",
   TO_CHAR(PINS,'999,999,999,999')                      \"Pins\",
   TO_CHAR(PINHITS,'999,999,999,999')                   \"PinHits\",
   TO_CHAR(PINHITRATIO,'99.99')                         \"PinHitRatio\",
   TO_CHAR(RELOADS,'999,999,999,999')                   \"Reloads\",
   TO_CHAR(INVALIDATIONS,'999,999,999,999')             \"Invalidations\"
FROM V\$LIBRARYCACHE
";

   $sql = "$copyright
SELECT
   NAMESPACE                                            \"Namespace\",
   TO_CHAR(GETS,'999,999,999,999')                      \"Gets\",
   TO_CHAR(GETHITS,'999,999,999,999')                   \"Get hits\",
   TO_CHAR(GETHITRATIO,'99.99')                         \"Get hit ratio\",
   TO_CHAR(PINS,'999,999,999,999')                      \"Pins\",
   TO_CHAR(PINHITS,'999,999,999,999')                   \"Pin hits\",
   TO_CHAR(PINHITRATIO,'99.99')                         \"Pin hit ratio\",
   TO_CHAR(RELOADS,'999,999,999,999')                   \"Reloads\",
   TO_CHAR(INVALIDATIONS,'999,999,999,999')             \"Invalidations\",
   TO_CHAR(DLM_LOCK_REQUESTS,'999,999,999,999')         \"DLM lock requests\",
   TO_CHAR(DLM_PIN_REQUESTS,'999,999,999,999')          \"DLM pin requests\",
   TO_CHAR(DLM_PIN_RELEASES,'999,999,999,999')          \"DLM pin releases\",
   TO_CHAR(DLM_INVALIDATION_REQUESTS,'999,999,999,999') \"DLM invalidation requests\",
   TO_CHAR(DLM_INVALIDATIONS,'999,999,999,999')         \"DLM invalidations\"
FROM V\$LIBRARYCACHE
" if ($oracle8 && parallel());

   $text = "Library cache information";
   $link = "";
   DisplayTable($sql,$text,$link);

# Resource limit info for Oracle8 databases.

   if ( ! $oracle7 ) {
      $sql = "$copyright
SELECT
   RESOURCE_NAME                \"Resource name\",
   INITIAL_ALLOCATION           \"Initial value\",
   CURRENT_UTILIZATION          \"Current utilization\",
   MAX_UTILIZATION              \"Max utilization\",
   LIMIT_VALUE                  \"Upper limit\"
FROM V\$RESOURCE_LIMIT
";

      $text = "Resource limits";
      $link = "";
      DisplayTable($sql,$text,$link);
   }

# Parallel query slave stats

   $sql = "$copyright
SELECT 
   SLAVE_NAME						\"Slave name\",
   STATUS						\"Status\",
   TO_CHAR(SESSIONS,'999,999,999,999')			\"Sessions\",
   TO_CHAR(IDLE_TIME_CUR,'999,999,999,999')		\"Idle time (cur)\",
   TO_CHAR(IDLE_TIME_TOTAL,'999,999,999,999')		\"Idle time (tot)\",
   TO_CHAR(BUSY_TIME_CUR,'999,999,999,999')		\"Busy time (cur)\",
   TO_CHAR(BUSY_TIME_TOTAL,'999,999,999,999')		\"Busy time (tot)\",
   TO_CHAR(CPU_SECS_CUR	,'999,999,999,999')		\"CPU seconds (cur)\",
   TO_CHAR(CPU_SECS_TOTAL,'999,999,999,999')		\"CPU seconds (tot)\",
   TO_CHAR(MSGS_SENT_CUR,'999,999,999,999')		\"Msgs sent (cur)\",
   TO_CHAR(MSGS_SENT_TOTAL,'999,999,999,999')		\"Msgs sent (tot)\",
   TO_CHAR(MSGS_RCVD_CUR,'999,999,999,999')		\"Msgs rcvd (cur)\",
   TO_CHAR(MSGS_RCVD_TOTAL,'999,999,999,999')		\"Msgs rcvd (tot)\"
FROM V\$PQ_SLAVE
";

      $text = "Parallel query slave statistics";
      $infotext = "No parallel query slaves are active";
      $link = "";
      DisplayTable($sql,$text,$link,$infotext);

# Parallel query server stats

   $sql = "$copyright
SELECT
   STATISTIC				\"Statistic\",
   TO_CHAR(VALUE,'999,999,999,999')	\"Value\" 
FROM V\$PQ_SYSSTAT
";

      $text = "Parallel query server status";
      $link = "";
      DisplayTable($sql,$text,$link);

   logit("Exit subroutine showPerformance");

}

sub getParameter {

   logit("Enter subroutine getParameter");

   my $name = shift;

   my ($sql,$cursor,$value);

   $sql = "$copyright
SELECT 
   VALUE 
FROM V\$PARAMETER
   WHERE NAME = '$name'
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $value = $cursor->fetchrow_array;
   $cursor->finish;

   logit("   Value for parameter $name is $value");

   logit("Exit subroutine getParameter");

   return($value);

}

sub showParameters {

   logit("Enter subroutine showParameters");

   my ($sql,$text,$link);

# Instance parameters

   $sql = "$copyright
SELECT 
   NAME			\"Name\",
   VALUE		\"Value\",
   DESCRIPTION		\"Description\",
   ISDEFAULT		\"Default\",
   ISSES_MODIFIABLE	\"Session mod\",
   ISSYS_MODIFIABLE	\"System mod\",
   ISADJUSTED		\"Changed\"
FROM V\$PARAMETER
   ORDER BY NAME
";

   $text = "Instance parameter information";
   $link = "";
   DisplayTable($sql,$text,$link);

   logit("Exit subroutine showParameters");

}

sub showRows {

   logit("Enter subroutine showRows");

   my $numrows = shift;

   my ($sql,$text,$link,$infotext,$error,$rowtext);

# Check to see if they want all rows..
# If so, set numrows to 1000000.
# Anyone wanting to see that many rows
# in a web browser is on drugs.

   if ($numrows eq "all") {
      $numrows = "1000000";
      $rowtext = "All";
   } else {
      $rowtext = $numrows;
   }

# If they entered a "where" clause, use it.

if ($whereclause) {
# Get rid of trailing semicolon, if present.
   $whereclause =~ s/;$//;
   $whereclause = " AND $whereclause";
}

# Show the first $numrows rows of a table

   $sql = "$copyright
SELECT * FROM $schema.$object_name 
WHERE ROWNUM <= $numrows
$whereclause
";

# See if there are actually less rows than the 
# number requested. Update $rowtext if so.

   $numrows = recordCount($dbh,$sql);
   unless ($rowtext eq "All") {
      $rowtext = $numrows;
   }

   $text = "$rowtext rows of $object_name";
   $link = "";
   $infotext = "There are no rows to display.";
   $error = DisplayTable($sql,$text,$link,$infotext);
   if (!($error =~ /^\d+$/)) {
      message("Error in your \"where\" clause.<BR>Check the SQL and try again.<BR><BR>$error");
   }

   logit("Exit subroutine showRows");

}

sub showRollback {

   logit("Enter subroutine showRollback");

   refreshButton();

   my ($sql,$text,$link,$infotext);

# Rollback segment information

   $sql = "$copyright
SELECT 
   A.NAME						\"Rollback name\",
   TO_CHAR(C.INITIAL_EXTENT,'999,999,999,999')		\"Initial extent\",
   TO_CHAR(C.NEXT_EXTENT,'999,999,999,999')		\"Next extent\",
   TO_CHAR(C.MIN_EXTENTS,'999,999,999,999')		\"Min extents\",
   B.EXTENTS						\"Extents\",
   TO_CHAR(C.MAX_EXTENTS,'999,999,999,999')		\"Max extents\",
   TO_CHAR(D.BYTES,'999,999,999,999')			\"Size\",
   NVL(TO_CHAR(B.OPTSIZE,'999,999,999,999'),'Not set')	\"Optimal\",
   TO_CHAR(B.EXTENDS,'999,999,999')			\"Extends\",
   TO_CHAR(B.SHRINKS,'999,999,999')			\"Shrinks\",
   TO_CHAR(B.WRAPS,'999,999,999')			\"Wraps\",
   B.STATUS						\"Status\"
FROM V\$ROLLNAME A, V\$ROLLSTAT B, DBA_ROLLBACK_SEGS C, DBA_SEGMENTS D
   WHERE A.NAME = '$object_name'
   AND C.SEGMENT_NAME = '$object_name'
   AND A.USN = B.USN
   AND D.SEGMENT_NAME = '$object_name'
   AND D.SEGMENT_TYPE = 'ROLLBACK'
";

   $text = "Rollback segment info";
   $link = "";
   DisplayTable($sql,$text,$link);

# Active transactions occupying this rollback

   $sql = "$copyright
SELECT 
   OSUSER				\"OS user\",
   USERNAME				\"Ora user\",
   SID                                  \"SID\",
   SERIAL#                              \"Serial#\",
   SEGMENT_NAME				\"RBS\",
   SA.SQL_TEXT				\"SQL Text\"
FROM   V\$SESSION S,
       V\$TRANSACTION T,
       DBA_ROLLBACK_SEGS R,
       V\$SQLAREA SA
WHERE  R.SEGMENT_NAME = '$object_name'
AND    S.TADDR = T.ADDR
AND    T.XIDUSN = R.SEGMENT_ID(+)
AND    S.SQL_ADDRESS = SA.ADDRESS(+)
";

   $text = "Transaction info";
   $link = "";
   $infotext = "No current transactions on this segment";
   DisplayTable($sql,$text,$link,$infotext);

# Tablespace information for the tablespace this rollback belongs to.
# Good for monitoring the growth of a rollback with a long running
# transaction.

   $sql = "$copyright
SELECT TABLESPACE_NAME 
   FROM DBA_SEGMENTS
WHERE SEGMENT_NAME = '$object_name'
AND SEGMENT_TYPE IN ('ROLLBACK','TYPE2 UNDO')
";

   my $cursor=$dbh->prepare($sql);
   $cursor->execute;
   $object_name = $cursor->fetchrow_array;
   $cursor->finish;

   $sql = "$copyright
SELECT * FROM
   (SELECT TO_CHAR(SUM(BYTES),'999,999,999,999')        \"Bytes allocated\"
FROM DBA_DATA_FILES WHERE TABLESPACE_NAME = '$object_name'),
   (SELECT TO_CHAR(SUM(BYTES),'999,999,999,999')        \"Bytes used\"
FROM DBA_EXTENTS WHERE TABLESPACE_NAME = '$object_name'),
   (SELECT TO_CHAR(SUM(BYTES),'999,999,999,999')        \"Bytes free\"
FROM DBA_FREE_SPACE WHERE TABLESPACE_NAME = '$object_name'),
   (SELECT TO_CHAR(MAX(BYTES),'999,999,999,999')        \"Largest free extent\"
FROM DBA_FREE_SPACE WHERE TABLESPACE_NAME = '$object_name')
";
   $text = "$object_name tablespace allocation";
   $link = "";
   DisplayTable($sql,$text,$link);

   logit("Exit subroutine showRollback");

}

sub showTransactions {

   logit("Enter subroutine showTransactions");

   my ($sql,$text,$link,$infotext,$refreshrate);

   $refreshrate = $ENV{'AUTO_REFRESH'} || "10";

# Display a refresh button

   unless ($norefreshbutton) {

      print <<"EOF";
  <FORM METHOD="POST" ACTION="$scriptname">
    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
    <INPUT TYPE=HIDDEN NAME=database    VALUE=$database>
    <INPUT TYPE=HIDDEN NAME=object_type VALUE=$object_type>
    <INPUT TYPE=HIDDEN NAME=arg         VALUE=$object_name>
    <INPUT TYPE=HIDDEN NAME=refreshrate VALUE=$refreshrate>
    <INPUT TYPE=SUBMIT NAME=foobar      VALUE=\"AutoRefresh ($refreshrate)\">
  </FORM>
  <P>
EOF

   }

# Check for transactions which are rolling back.

   $sql = "$copyright
SELECT
   S.USERNAME					\"Username\",
   S.SID					\"SID\",
   S.SERIAL#					\"Serial#\",
   TO_CHAR(T.USED_UBLK,'999,999,999,999,999')	\"Used undo blocks\",
   DRS.SEGMENT_NAME				\"RBS name\"
FROM V\$SESSION S,
     V\$TRANSACTION T,
     DBA_ROLLBACK_SEGS DRS
   WHERE T.ADDR IN
(SELECT
   ADDR
FROM V\$TRANSACTION 
   WHERE FLAG = 7811)
   AND S.TADDR IN
(SELECT
   ADDR
FROM V\$TRANSACTION
   WHERE FLAG = 7811)
   AND T.ADDR = S.TADDR
   AND T.XIDUSN = DRS.SEGMENT_ID
";

   $text = "The following sessions appear to be in a rollback status.";
   $infotext = "No transactions are in a rollback status.";
   $link = "$scriptname?database=$database&object_type=TOPSESSIONS";
   DisplayTable($sql,$text,$link,$infotext);

# Active transactions occupying all rollbacks

   $sql = "$copyright
SELECT
   SEGMENT_NAME                         \"RBS\",
   OSUSER                               \"OS user\",
   USERNAME                             \"Ora user\",
   SID					\"SID\",
   SERIAL#				\"Serial#\",
   SA.SQL_TEXT                          \"SQL Text\"
FROM   V\$SESSION S,
       V\$TRANSACTION T,
       DBA_ROLLBACK_SEGS R,
       V\$SQLAREA SA
WHERE    S.TADDR = T.ADDR
AND    T.XIDUSN = R.SEGMENT_ID(+)
AND    S.SQL_ADDRESS = SA.ADDRESS(+)
";

   $text = "Transaction info";
   $link = "$scriptname?database=$database&object_type=ROLLBACK";
   $infotext = "No transactions active on any segments.";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine showTransactions");

}

sub showRollbacks {

   logit("Enter subroutine showRollbacks");

   my ($sql,$cursor,$foo,$text,$link,$infotext);
   my ($tablespace_name,$undo_block_size);

# Display a refresh button

   refreshButton();

   if ($oracle9i || $oracle10) {
      if (getParameter("undo_management") eq "AUTO") {
         logit("   undo_management is set to AUTO.");
         $sql = "
SELECT
   TABLESPACE_NAME,
   BLOCK_SIZE
FROM DBA_TABLESPACES
   WHERE CONTENTS = 'UNDO'
";
         $cursor = $dbh->prepare($sql);
         $cursor->execute;
         ($tablespace_name,$undo_block_size) = $cursor->fetchrow_array;
         $cursor->finish;
         logit("   UNDO TS is $tablespace_name, block size of $undo_block_size");

   # Check for ORA-1555 errors

         $sql = "$copyright
SELECT  
   TSD.NAME							\"Tablespace name\",
   TO_CHAR(VUS.SSOLDERRCNT,'999,999,999,999')			\"ORA-1555 indications #\",
   TO_CHAR(VUS.BEGIN_TIME,'Month DD, YYYY - HH24:MI')		\"Period start time\",
   TO_CHAR(VUS.END_TIME,'Month DD, YYYY - HH24:MI')		\"Period end time\",
   TO_CHAR((VUS.MAXQUERYLEN/60),'999,999,999,999')		\"Max query len (minutes)\",
   TO_CHAR(VUS.TXNCOUNT,'999,999,999,999')			\"Transaction count\",
   TO_CHAR(VUS.UNDOBLKS,'999,999,999,999')			\"UNDO blocks used\",
   TO_CHAR((VUS.UNDOBLKS*TSD.BLOCKSIZE),'999,999,999,999')	\"UNDO bytes used\"
FROM SYS.TS\$ TSD, V\$UNDOSTAT VUS
   WHERE TSD.TS# = VUS.UNDOTSN
   AND VUS.SSOLDERRCNT > 0
";

         $text = "Warning: Snapshot too old errors have been logged within the past 7 days.";
         $link = "";
         $infotext = "No snapshot too old errors have been logged within the past 7 days.";
         DisplayTable($sql,$text,$link,$infotext);

   # Check for tablespace out of space errors

         $sql = "$copyright
SELECT  
   TSD.NAME							\"Tablespace name\",
   TO_CHAR(VUS.NOSPACEERRCNT,'999,999,999,999')			\"TS out of space indications\",
   TO_CHAR(VUS.BEGIN_TIME,'Month DD, YYYY - HH24:MI')		\"Period start time\",
   TO_CHAR(VUS.END_TIME,'Month DD, YYYY - HH24:MI')		\"Period end time\",
   TO_CHAR((VUS.MAXQUERYLEN/60),'999,999,999,999')		\"Max query len (minutes)\",
   TO_CHAR(VUS.TXNCOUNT,'999,999,999,999')			\"Transaction count\",
   TO_CHAR(VUS.UNDOBLKS,'999,999,999,999')			\"UNDO blocks used\",
   TO_CHAR((VUS.UNDOBLKS*TSD.BLOCKSIZE),'999,999,999,999')	\"UNDO bytes used\"
FROM SYS.TS\$ TSD, V\$UNDOSTAT VUS
   WHERE TSD.TS# = VUS.UNDOTSN
   AND NOSPACEERRCNT > 0
";

         $text = "Warning: Tablespace out of space errors have been logged within the past 7 days.";
         $link = "";
         $infotext = "No tablespace out of space errors have been logged within the past 7 days.";
         DisplayTable($sql,$text,$link,$infotext);

      } else {
         logit("   We are 9i, but not using automatic undo_management.");
      }
   }

# Rollback segment information

   $sql = "$copyright
SELECT
   A.SEGMENT_NAME					\"Name\",
   A.OWNER						\"Owner\",
   A.TABLESPACE_NAME					\"Tablespace\",
   TO_CHAR(A.BYTES,'999,999,999,999')			\"Bytes\",
   TO_CHAR(A.INITIAL_EXTENT,'999,999,999,999')		\"Initial Extent\",
   TO_CHAR(A.NEXT_EXTENT,'999,999,999,999')		\"Next extent\",
   TO_CHAR(A.EXTENTS,'999,999,999,999')			\"Extents\",
   TO_CHAR(A.MAX_EXTENTS,'999,999,999,999')		\"Max Extents\",
   NVL(TO_CHAR(C.OPTSIZE,'999,999,999,999'),'Not set')	\"Optimal\",
   NVL(TO_CHAR(C.EXTENDS,'999,999,999,999'),'Not set')	\"Extends\",
   NVL(TO_CHAR(C.SHRINKS,'999,999,999,999'),'Not set')	\"Shrinks\",
   B.STATUS						\"Status\",
   TO_CHAR(C.WRITES,'999,999,999,999,999')		\"Writes\",
   C.WAITS						\"Waits\",
   C.XACTS						\"Active Xacts\"
FROM DBA_SEGMENTS A, DBA_ROLLBACK_SEGS B, V\$ROLLSTAT C
   WHERE A.SEGMENT_TYPE IN ('ROLLBACK','TYPE2 UNDO')
   AND A.SEGMENT_NAME = B.SEGMENT_NAME
   AND B.SEGMENT_ID = C.USN
   AND ( B.INSTANCE_NUM = 
      ( SELECT VALUE FROM V\$PARAMETER
           WHERE NAME = 'instance_number' )
         OR B.INSTANCE_NUM IS NULL )
ORDER BY A.SEGMENT_NAME, A.TABLESPACE_NAME
";

   $text = "Online rollback segments";
   $link = "$scriptname?database=$database&object_type=ROLLBACK";
   DisplayTable($sql,$text,$link);

   $sql = "$copyright
SELECT
   SEGMENT_NAME		\"Name\",
   STATUS		\"Status\",
   OWNER		\"Owner\",
   TABLESPACE_NAME	\"Tablespace\"
FROM DBA_ROLLBACK_SEGS
   WHERE STATUS != 'ONLINE'
";

   $text = "Warning: You have rollback(s) which are not online";
   $link = "$scriptname?database=$database&object_type=ROLLBACK";
   DisplayTable($sql,$text,$link);

# Show gets and waits percentages for performance 

   $sql = "$copyright
SELECT 
   SUM(VALUE)
FROM V\$SYSSTAT
   WHERE NAME IN
('db block gets','consistent gets')
";
   $cursor=$dbh->prepare($sql);
   $cursor->execute;
   $foo = $cursor->fetchrow_array;
   $cursor->finish;

   $sql = "$copyright
SELECT 
   TO_CHAR(SUM(VALUE),'999,999,999,999,999,999,999') \"Total gets\"
FROM V\$SYSSTAT
   WHERE NAME IN
('db block gets','consistent gets')
";
   $text = "Total gets";
   $link = "";
   DisplayTable($sql,$text,$link);
   
   $sql = "$copyright
SELECT 
   CLASS				\"Class\",
   TO_CHAR(COUNT,'999,999,999,999')	\"Count\", 
   TO_CHAR(COUNT/$foo,'99.99')		\"Wait %\"
   FROM V\$WAITSTAT
WHERE CLASS IN
('system undo header','system undo block','undo header','undo block')
";

   $text = "Wait statistics.<BR>If any wait% is greater than 1, you may need to add rollbacks.";
   $link = "";
   DisplayTable($sql,$text,$link);

   $sql = "$copyright
SELECT
   DF.TABLESPACE_NAME						\"Tablespace name\",
   TO_CHAR(DF.BYTES,'999,999,999,999')				\"Bytes allocated\",
   NVL(TO_CHAR(DF.BYTES-SUM(FS.BYTES),'999,999,999,999'),
        TO_CHAR(DF.BYTES,'999,999,999,999'))			\"Bytes used\",
   NVL(TO_CHAR(SUM(FS.BYTES),'999,999,999,999'),0)		\"Bytes free\",
   NVL(ROUND((DF.BYTES-SUM(FS.BYTES))*100/DF.BYTES),100)||'%'	\"Percent used\",
   NVL(ROUND(SUM(FS.BYTES)*100/DF.BYTES),0)||'%'		\"Percent free\"
FROM DBA_FREE_SPACE FS,
   (SELECT TABLESPACE_NAME, SUM(BYTES) BYTES FROM DBA_DATA_FILES GROUP BY
TABLESPACE_NAME ) DF
WHERE FS.TABLESPACE_NAME (+) = DF.TABLESPACE_NAME
AND DF.TABLESPACE_NAME IN (
   SELECT DISTINCT TABLESPACE_NAME
      FROM DBA_ROLLBACK_SEGS )
GROUP BY DF.TABLESPACE_NAME, DF.BYTES
ORDER BY \"Percent free\"
";

   $text = "Tablespaces containing rollback segments.";
   $link = "";
   DisplayTable($sql,$text,$link);

   logit("Exit subroutine showRollbacks");

}

sub showContention {

   logit("Enter subroutine showContention");

   my ($sql,$text,$link,$infotext,$count);
   my ($holding_sid,$holding_serial,$holding_username,$owner,$object_name,$waiting_sid,$waiting_serial,$waiting_username,$mode_held);

   refreshButton();

# Locking contention information

   $sql = "$copyright
SELECT DISTINCT 
   SH.SID,
   SH.SERIAL#,
   SH.USERNAME,
   O.OWNER,
   O.OBJECT_NAME,
   SW.SID,
   SW.SERIAL#,
   SW.USERNAME,
   DECODE(LH.LMODE,
	1, 'null', 
	2, 'row share', 
	3, 'row exclusive', 
	4, 'share', 
	5, 'share row exclusive', 
	6, 'exclusive')
  FROM DBA_OBJECTS O,
       V\$SESSION SW, 
       V\$LOCK LW, 
       V\$SESSION SH, 
       V\$LOCK LH
WHERE LH.ID1  = O.OBJECT_ID
AND  LH.ID1  = LW.ID1
AND  SH.SID  = LH.SID
AND  SW.SID  = LW.SID
AND  SH.LOCKWAIT IS NULL
AND  SW.LOCKWAIT IS NOT NULL
AND  LH.TYPE = 'TM'
AND  LW.TYPE = 'TM'
";

   $count = recordCount($dbh,$sql);

   # Print the heading

   if ($count == 0) {
      text("No object lock contention found");
   } else {
      text("Object lock contention info");

   print <<"EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Holding SID</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Holding Username</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Object Name</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Waiting Username</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Waiting SID</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Mode Held</TH>
EOF

   $cursor = $dbh->prepare($sql);
   $cursor->execute;

   while (($holding_sid,$holding_serial,$holding_username,$owner,$object_name,$waiting_sid,$waiting_serial,$waiting_username,$mode_held) = $cursor->fetchrow_array) {
      $count++;
      $object_name = "$owner.$object_name";
      print <<"EOF";
        <tr>
          <td align=center bgcolor='$cellcolor'><font color='$fontcolor' size='$fontsize' face='$font'><a href=$scriptname?database=$database&object_type=SESSIONINFO&sid=$holding_sid&serial=$holding_serial&user=$holding_username&page=general>$holding_sid</a></td>
          <td align=center bgcolor='$cellcolor'><font color='$fontcolor' size='$fontsize' face='$font'>$holding_username</td>
          <td align=center bgcolor='$cellcolor'><font color='$fontcolor' size='$fontsize' face='$font'>$object_name</td>
          <td align=center bgcolor='$cellcolor'><font color='$fontcolor' size='$fontsize' face='$font'>$waiting_username</td>
          <td align=center bgcolor='$cellcolor'><font color='$fontcolor' size='$fontsize' face='$font'><a href=$scriptname?database=$database&object_type=SESSIONINFO&sid=$waiting_sid&serial=$waiting_serial&user=$waiting_username&page=general>$waiting_sid</a></td>
          <td align=center bgcolor='$cellcolor'><font color='$fontcolor' size='$fontsize' face='$font'>$mode_held</td>
        </tr>
EOF
   }
   $cursor->finish;
   print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF

   }

# Locked objects (Not neccessarily contending).

   $sql = "$copyright
SELECT 
   A.OBJECT_NAME				\"Object_name\",
   A.OWNER					\"Owner\",
   B.OBJECT_ID					\"Object ID\",
   B.SESSION_ID					\"SID\",
   B.ORACLE_USERNAME				\"Oracle user\",
   B.PROCESS					\"OS process ID\",
   DECODE(B.LOCKED_MODE,
			0,'None',
			1,'Null',
			2,'Row-S (SS)',
			3,'Row-X (SX)',
			4,'Share',
			5,'S/Row-X (SSX)',
			6,'Exclusive')		\"Locked mode\"
FROM DBA_OBJECTS A, V\$LOCKED_OBJECT B
   WHERE A.OBJECT_ID = B.OBJECT_ID
ORDER BY 1,2,3
";

   $text = "Object lock info";
   $link = "";
   $infotext = "No object locks found.";
   DisplayTable($sql,$text,$link,$infotext);

   # Latch wait info..

   $sql = "
Select 
   parent_name						\"Name\",
   to_char(sleep_count,'999,999,999,999,999')		\"Sleep count\"
 from v\$latch_misses 
where sleep_count > 
   (Select 
      max(sleep_count)-(max(sleep_count)*.25) 
   from v\$latch_misses)
   order by sleep_count desc
";

   $text = "Latch wait history, top 25%";
   $link = "";
   $infotext = "No latch wait history found.";
   DisplayTable($sql,$text,$link,$infotext);

# Session wait information
# Not so sure that this is important anymore, the session
# summary makes it easy to see if a session is in wait or not. 
# Or, maybe it just needs to be improved..

# $sql = "$copyright
# SELECT 
#    SES.USERNAME				\"Username\",
#    SW.SID				\"SID\",
#    SW.EVENT				\"Event\"
# FROM V\$SESSION SES,
#      V\$SESSION_WAIT SW
# WHERE SES.SID = SW.SID
# AND SES.USERNAME IS NOT NULL
# ";

#    $text = "Session wait info";
#    $link = "";
#    $infotext = "No waits found.";
#    DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine showContention");

}

sub showRefreshgroups {

   logit("Enter subroutine showRefreshgroups");

   my ($sql,$cursor,$text,$link,$infotext);

#   $sql = "$copyright
#SELECT
#   OWNER		\"Refresh owner\",
#   NAME			\"Refresh Name\",
#   TABLE_NAME		\"Table name\",
#   MASTER_VIEW		\"Master view\",
#   MASTER_OWNER		\"Master owner\",
#   MASTER		\"Master table\",
#   MASTER_LINK		\"DB link\",
#   CAN_USE_LOG		\"Log?\",
#   UPDATABLE		\"Updatable?\",
#   TO_CHAR(LAST_REFRESH,'Month DD, YYYY - HH24:MI') \"Last refresh\"
#FROM DBA_SNAPSHOTS
#";

#   $text = "Parent snapshots";
#   $link = "$scriptname?database=$database&object_type=SNAPINFO";
#   $infotext = "";
#   DisplayTable($sql,$text,$link,$infotext);

   $sql = "$copyright
SELECT 
   REFGROUP						\"Group ID\",
   ROWNER						\"Group owner\",
   RNAME						\"Group name\",
   ROLLBACK_SEG						\"Rollback\",
   PUSH_DEFERRED_RPC					\"Push changes?\",
   JOB							\"Job ID\",
   TO_CHAR(NEXT_DATE,'Month DD, YYYY - HH24:MI')		\"Next date\",
   BROKEN						\"Broken?\",
   PURGE_OPTION						\"Purge option\",
   PARALLELISM						\"Parallelism\"
FROM DBA_REFRESH
";

   $text = "Refresh groups";
   $link = "$scriptname?database=$database&object_type=REFRESHINFO";
   $infotext = "No refresh groups";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine showRefreshgroups");

}

sub showRefreshinfo {

   logit("Enter subroutine showRefreshinfo");

   my ($sql,$cursor,$text,$link,$infotext);

   $sql = "$copyright
SELECT
   OWNER						\"Owner\",
   NAME							\"Name\",
   TYPE							\"Type\",
   ROLLBACK_SEG						\"Rollback\",
   PUSH_DEFERRED_RPC					\"Push changes?\",
   JOB							\"Job ID\",
   TO_CHAR(NEXT_DATE,'Month DD, YYYY - HH24:MI')		\"Next date\",
   BROKEN						\"Broken?\",
   PURGE_OPTION						\"Purge option\",
   PARALLELISM						\"Parallelism\"
FROM DBA_REFRESH_CHILDREN
   WHERE REFGROUP = $object_name
";

   $text = "Refresh group children";
   $link = "";
   $infotext = "No refresh group children";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine showRefreshinfo");

}

sub showAdvRepGroup {

   logit("Enter subroutine showAdvRepGroup");

   my ($sql,$cursor,$text,$link,$infotext); 

   $sql = "$copyright
SELECT 
   DBLINK			\"DB link\",
   MASTERDEF			\"Masterdef\",
   SNAPMASTER			\"Snap link\",
   MASTER_COMMENT		\"Comment\",
   DECODE(MASTER,
                 'Y','YES',
                 'N','NO')      \"Master?\"
FROM DBA_REPSITES
   WHERE GNAME = '$object_name'
ORDER BY MASTERDEF DESC
   ";

   $text = "Information for replicated group $object_name.";
   $link = "";
   $infotext = "";
   DisplayTable($sql,$text,$link,$infotext);

   $sql = "$copyright
SELECT 
   SNAME			\"Owner\",
   ONAME			\"Object name\",
   TYPE				\"Object type\",
   STATUS			\"Status\",
   GENERATION_STATUS		\"Generation status\",
   ID				\"ID\",
   OBJECT_COMMENT		\"Comment\"
FROM DBA_REPOBJECT
   WHERE GNAME = '$object_name'
ORDER BY TYPE DESC
";

   $text = "";
   $link = "";
   $infotext = "";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine showAdvRepGroup");

}

sub showAdvRepGroups {

   logit("Enter subroutine showAdvRepGroups");

   my ($sql,$cursor,$text,$link,$infotext);

   $sql = "$copyright
SELECT 
   GNAME 			\"Group name\",
   DECODE(MASTER,
                 'Y','YES',
                 'N','NO')	\"Master?\",
   STATUS			\"Status\",
   SCHEMA_COMMENT		\"Comment\"
FROM DBA_REPGROUP
   ORDER BY MASTER
";

   $text = "Advanced replication group(s)";
   $link = "$scriptname?database=$database&object_type=ADVREPGROUP";
   $infotext = "";
   DisplayTable($sql,$text,$link,$infotext);

   $sql = "$copyright
SELECT 
   TO_CHAR(ID,'999,999,999,999')			\"ID\",
   SOURCE						\"Source\",
   USERID						\"User ID\",
   TO_CHAR(TIMESTAMP,'Month DD, YYYY - HH24:MI')	\"Timestamp\",
   ROLE							\"Role\",
   MASTER						\"Master\",
   SNAME						\"Remote schema\",
   REQUEST						\"Request\",
   ONAME						\"Object_name\",
   TYPE							\"Object type\",
   STATUS						\"Status\",
   MESSAGE						\"Message\",
   ERRNUM						\"Ora error\",
   GNAME						\"Group name\"
FROM DBA_REPCATLOG
";

   $text = "Repcatlog entries";
   $link = "";
   $infotext = "No entries in the Repcatlog table.";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine showAdvRepGroups");

}

sub showRepmaster {

   logit("Enter subroutine showRepmaster");

   my ($sql,$cursor,$text,$link,$infotext);

   $sql = "$copyright
SELECT
   SNAPSHOT_ID		\"Snap ID\",
   NAME			\"Name\",
   OWNER		\"Owner\",
   SNAPSHOT_SITE	\"Snap site\",
   CAN_USE_LOG		\"Use log?\",
   UPDATABLE		\"Updatable?\",
   REFRESH_METHOD	\"Refresh method\",
   VERSION		\"Version\"
FROM DBA_REGISTERED_SNAPSHOTS
";

   $text = "Registered snapshots";
   $link = "$scriptname?database=$database&object_type=SNAPINFO";
   $infotext = "";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine showRepmaster");

}   

sub showSnapinfo {

   logit("Enter subroutine showSnapinfo");

   my ($sql,$cursor,$text,$link,$infotext);

   $sql = "$copyright
SELECT
   NAME			\"Name\",
   OWNER		\"Owner\",
   SNAPSHOT_SITE	\"Snap site\"
FROM DBA_REGISTERED_SNAPSHOTS
   WHERE SNAPSHOT_ID = $object_name
";

   $text = "Detailed snapshot info";
   $link = "";
   $infotext = "";
   DisplayTable($sql,$text,$link,$infotext);

   $sql = "$copyright
SELECT 
   QUERY_TXT		\"Query text\"
FROM DBA_REGISTERED_SNAPSHOTS
   WHERE SNAPSHOT_ID = $object_name
";

   $text = "";
   DisplayPiecedData($sql,$text);

   $sql = "$copyright
SELECT 
   LOG_TABLE		\"Log table\",
   MASTER		\"Master\",
   LOG_OWNER		\"Log owner\",
   ROWIDS		\"Rowids?\",
   PRIMARY_KEY		\"Primary key?\",
   FILTER_COLUMNS	\"Filter columns?\",
   TO_CHAR(CURRENT_SNAPSHOTS,'Month DD, YYYY - HH24:MI') \"Current snapshot\"
FROM DBA_SNAPSHOT_LOGS
   WHERE SNAPSHOT_ID = $object_name
";
   

   $text = "Snapshot log table";
   $link = "";
   $infotext = "No snapshot log table for this snapshot.";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine showSnapinfo");

}

sub showControlfiles {

   logit("Enter subroutine showControlfiles");

   my ($sql,$cursor,$text,$link,$infotext);
   my ($alloc,$used,$alloc_total,$used_total);

   $sql = "$copyright
SELECT
   NAME				\"Name\",
   DECODE (STATUS,'','OK')	\"Status\"
FROM V\$CONTROLFILE
";

   $text = "Controlfile info";
   $link = "";
   $infotext = "There is something terribly wrong...";
   DisplayTable($sql,$text,$link,$infotext);

   if (! $oracle7) {

      $sql = "$copyright
SELECT 
   RECORDS_TOTAL*RECORD_SIZE,
   RECORDS_USED*RECORD_SIZE
FROM V\$CONTROLFILE_RECORD_SECTION
";

   $cursor=$dbh->prepare($sql);
   $cursor->execute;
   while (($alloc,$used) = $cursor->fetchrow_array) {
      $alloc_total += $alloc;
      $used_total  += $used;
   }
   $cursor->finish;

   $sql = "$copyright
SELECT 
   TO_CHAR($alloc_total,'999,999,999,999')	\"Total allocated\",
   TO_CHAR($used_total,'999,999,999,999')	\"Total used\"
FROM DUAL
";

   $text = "Controlfile record space usage";
   $link = "";
   $infotext = "There is something terribly wrong...";
   DisplayTable($sql,$text,$link,$infotext);

      $sql = "$copyright
SELECT
   DECODE(TYPE,
      'DATABASE','Database',
      'CKPT PROGRESS','Checkpoint progress',
      'REDO THREAD','Redo thread',
      'REDO LOG','Redo log',
      'DATAFILE','Datafile',
      'FILENAME','Filename',
      'TABLESPACE','Tablespace',
      'LOG HISTORY','Log history',
      'OFFLINE RANGE','Offline range',
      'ARCHIVED LOG','Archived log',
      'BACKUP SET','Backup set',
      'BACKUP PIECE','Backup piece',
      'BACKUP DATAFILE','Backup datafile',
      'BACKUP REDOLOG','Backup redolog',
      'DATAFILE COPY','Datafile copy',
      'BACKUP CORRUPTION','Backup corruption',
      'COPY CORRUPTION','Copy corruption',
      'DELETED OBJECT','Deleted object','Reserved')			\"Record type\",
   TO_CHAR(RECORD_SIZE,'999,999,999,999')				\"Record size\",
   TO_CHAR(RECORDS_TOTAL,'999,999,999,999')				\"Records total\",
   TO_CHAR(RECORDS_USED,'999,999,999,999')				\"Records used\",
   TO_CHAR(RECORDS_TOTAL*RECORD_SIZE,'999,999,999,999')			\"Space allocated\",
   TO_CHAR(RECORDS_USED*RECORD_SIZE,'999,999,999,999')			\"Space used\"
FROM V\$CONTROLFILE_RECORD_SECTION
";

   $text = "Controlfile record info";
   $link = "";
   $infotext = "There is something terribly wrong...";
   DisplayTable($sql,$text,$link,$infotext);

   }

   logit("Exit subroutine showControlfiles");

}


sub showArchiving {

   logit("Enter subroutine showArchiving");

   my ($sql,$cursor,$value,$log_archive_dest,$text,$link,$infotext);

   $sql = "$copyright
SELECT 
   VALUE FROM V\$PARAMETER
WHERE NAME = 'log_archive_dest'
";

   $cursor=$dbh->prepare($sql);
   $cursor->execute;
   $value = $cursor->fetchrow_array;

   $log_archive_dest .= $value;

   $sql = "$copyright
SELECT 
   VALUE FROM V\$PARAMETER
WHERE NAME = 'log_archive_format'
";

   $cursor=$dbh->prepare($sql);
   $cursor->execute;
   $value = $cursor->fetchrow_array;

   $log_archive_dest .= $value;

   $sql = "$copyright
SELECT '$log_archive_dest' \"Archive log format\" FROM DUAL
";

   $text = "";
   $link = "";
   $infotext = "";
   DisplayTable($sql,$text,$link,$infotext);
   
   $sql = "$copyright
SELECT 
   THREAD#							\"Thread#\",
   SEQUENCE#							\"Sequence#\",
   TIME								\"Time of first entry\",
   LOW_CHANGE#							\"Lowest  SCN\",
   (HIGH_CHANGE#-1)						\"Highest SCN\",
   ARCHIVE_NAME							\"Archived log name\"
FROM V\$LOG_HISTORY
ORDER BY SEQUENCE# DESC
" if ($oracle7);

   $sql = "$copyright
SELECT 
   THREAD#							\"Thread#\",
   SEQUENCE#							\"Sequence#\",
   TO_CHAR(FIRST_TIME,'Day, Month DD YYYY - HH24:MI:SS')	\"Time of first entry\",
   FIRST_CHANGE#						\"Lowest  SCN\",
   NEXT_CHANGE#							\"Highest SCN\",
   RECID							\"Controlfile RecID\",
   STAMP							\"Controlfile stamp\"
FROM V\$LOG_HISTORY
ORDER BY SEQUENCE# DESC
" if (! $oracle7);

   $sql = "$copyright
SELECT 
   THREAD#							\"Thread#\",
   SEQUENCE#							\"Sequence#\",
   TO_CHAR(FIRST_TIME,'Day, Month DD YYYY - HH24:MI:SS')	\"Time of first entry\",
   FIRST_CHANGE#						\"Lowest  SCN\",
   NEXT_CHANGE#							\"Highest SCN\",
   RECID							\"Controlfile RecID\",
   STAMP							\"Controlfile stamp\"
FROM V\$LOG_HISTORY
   WHERE THREAD# = (
SELECT VALUE FROM V\$PARAMETER
   WHERE NAME = 'thread')
ORDER BY SEQUENCE# DESC
" if ( (! $oracle7) && (parallel()) );

   $sql = "$copyright
SELECT 
   NAME								\"Name\",
   SEQUENCE#							\"Sequence#\",
   TO_CHAR(FIRST_TIME,'Day, Month DD YYYY - HH24:MI:SS')	\"Time of first entry\",
   FIRST_CHANGE#						\"Lowest  SCN\",
   TO_CHAR(NEXT_TIME,'Day, Month DD YYYY - HH24:MI:SS')		\"Time of last entry\",
   NEXT_CHANGE#							\"Highest SCN\",
   RECID							\"Controlfile RecID\",
   STAMP							\"Controlfile stamp\"
FROM V\$ARCHIVED_LOG
ORDER BY SEQUENCE# DESC
" if ($oracle9i);

   $text = "Archived redo log info";
   $link = "";
   $infotext = "There are no archived redologs to report on.";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine showArchiving");

}

sub showRedo {

   logit("Enter subroutine showRedo");

   my ($sql,$cursor,$value,$text,$link,$count);
   my ($block_size,%blockhash,$blocks,$hour,@hours);
   my ($bytes,$running_total,$comma_total);

   refreshButton();

   if ($oracle10 || $oracle11) {

      $sql  = "$copyright Select flashback_on from v\$database";

      $cursor=$dbh->prepare($sql);
      $cursor->execute;
      $value = $cursor->fetchrow_array;
      if ( $value eq "YES" ) {
         Button("$scriptname?object_type=FLASHBACKINFO&database=$database","Flashback information","$headingcolor","CENTER","200");
      }

      $sql = "$copyright
Select
   log_mode 
from v\$database
";
   } else {

      $sql = "$copyright
SELECT
   VALUE FROM V\$PARAMETER
WHERE NAME = 'log_archive_start'
";
   }

   $cursor=$dbh->prepare($sql);
   $cursor->execute;
   $value = $cursor->fetchrow_array;

   if ( $value eq "ARCHIVELOG" || $value eq "STARTED" ) {
      Button("$scriptname?object_type=ARCHIVING&database=$database","Archived log information","$headingcolor","CENTER","200");
    } else {
      message("Database archiving is not enabled.");
   }


# Online redo log information

   $sql = "$copyright
SELECT
   A.MEMBER				\"Member\",
   B.GROUP#				\"Group#\",
   B.THREAD#				\"Thread#\",
   B.SEQUENCE#				\"Sequence#\",
   TO_CHAR(B.BYTES,'999,999,999,999')	\"Bytes\",
   B.MEMBERS				\"Members\",
   B.ARCHIVED				\"Archived\",
   B.STATUS				\"Status\"
FROM V\$LOGFILE A, V\$LOG B
   WHERE A.GROUP# = B.GROUP#
ORDER BY 4 DESC
";

   $text = "Online redo log info";
   $link = "";
   DisplayTable($sql,$text,$link);

   $sql = "$copyright
SELECT
   TO_CHAR(TRUNC(FIRST_TIME),'Mon DD')			\"Date\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'00',1,0)),'9999')	\"00\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'01',1,0)),'9999')	\"01\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'02',1,0)),'9999')	\"02\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'03',1,0)),'9999')	\"03\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'04',1,0)),'9999')	\"04\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'05',1,0)),'9999')	\"05\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'06',1,0)),'9999')	\"06\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'07',1,0)),'9999')	\"07\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'08',1,0)),'9999')	\"08\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'09',1,0)),'9999')	\"09\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'10',1,0)),'9999')	\"10\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'11',1,0)),'9999')	\"11\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'12',1,0)),'9999')	\"12\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'13',1,0)),'9999')	\"13\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'14',1,0)),'9999')	\"14\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'15',1,0)),'9999')	\"15\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'16',1,0)),'9999')	\"16\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'17',1,0)),'9999')	\"17\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'18',1,0)),'9999')	\"18\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'19',1,0)),'9999')	\"19\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'20',1,0)),'9999')	\"20\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'21',1,0)),'9999')	\"21\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'22',1,0)),'9999')	\"22\",
   TO_CHAR(SUM(DECODE(TO_CHAR(FIRST_TIME,'HH24'),'23',1,0)),'9999')	\"23\"
FROM V\$LOG_HISTORY
   GROUP BY TRUNC(FIRST_TIME)
   ORDER BY TRUNC(FIRST_TIME) DESC
" if $notoracle7;

   $sql = "$copyright
SELECT
   SUBSTR(TIME,1,5)			\"Day\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'00',1,0)),'9999')	\"00\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'01',1,0)),'9999')	\"01\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'02',1,0)),'9999')	\"02\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'03',1,0)),'9999')	\"03\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'04',1,0)),'9999')	\"04\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'05',1,0)),'9999')	\"05\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'06',1,0)),'9999')	\"06\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'07',1,0)),'9999')	\"07\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'08',1,0)),'9999')	\"08\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'09',1,0)),'9999')	\"09\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'10',1,0)),'9999')	\"10\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'11',1,0)),'9999')	\"11\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'12',1,0)),'9999')	\"12\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'13',1,0)),'9999')	\"13\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'14',1,0)),'9999')	\"14\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'15',1,0)),'9999')	\"15\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'16',1,0)),'9999')	\"16\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'17',1,0)),'9999')	\"17\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'18',1,0)),'9999')	\"18\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'19',1,0)),'9999')	\"19\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'20',1,0)),'9999')	\"20\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'21',1,0)),'9999')	\"21\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'22',1,0)),'9999')	\"22\",
   TO_CHAR(SUM(DECODE(SUBSTR(TIME,10,2),'23',1,0)),'9999')	\"23\"
FROM V\$LOG_HISTORY
   GROUP BY SUBSTR(TIME,1,5)
" if $oracle7;

   $text = "Graph of log switch history by day and hour";
   $link = "";
   DisplayTable($sql,$text,$link);

   # Show information on space taken up by archived redo logs
   # if archiving is enabled.
   if ( $value eq "TRUE" ) {

      text("Summary of space usage for archived redo logs, last 24 hours");

      print <<"EOF";
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0 ALIGN=CENTER>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Hour</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Logs written #</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Bytes written</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Running total</TH>
EOF

      # Get the block size
      $sql = "
Select block_size
   from v\$archived_log
where rownum < 2
";
      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      $block_size = $cursor->fetchrow_array;
      $cursor->finish;
      logit("   Archived log block size is $block_size");

      @hours = ('00','01','02','03','04','05','06','07','08','09','10','11','12','13','14','15','16','17','18','19','20','21','22','23');
      foreach $hour(@hours) {
         $sql = "
Select sum(blocks)*$block_size, count(*)
   from v\$archived_log
where completion_time > sysdate-1
   and to_char(completion_time,'HH24') = '$hour'
";
         $cursor = $dbh->prepare($sql);
         $cursor->execute;
         ($blocks,$count) = $cursor->fetchrow_array;
         $cursor->finish;
         $bytes = commify($blocks + ($count*$block_size));
         $running_total += $blocks + ($count*$block_size);
         $comma_total = commify($running_total);
         $count = commify($count);
         logit("   Archived logs for hour $hour total $bytes ($count logs)");
         print <<"EOF";
        <TR>
          <TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$hour</TD>
          <TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$count</TD>
          <TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$bytes</TD>
          <TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$comma_total</TD>
        </TR>
EOF
      }
      $running_total = commify($running_total);
      logit("   Total archive space used past 24 hours: $running_total");
   }
   print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF
      
   logit("Exit subroutine showRedo");

}

sub checkPriv {

   logit("Enter subroutine checkPriv");

   my ($privilege,$yesno);

   $privilege = shift;

   logit("   Checking for privilege \"$privilege\"");

   $sql = "$copyright
SELECT
   COUNT(*)
FROM SESSION_PRIVS
   WHERE PRIVILEGE = '$privilege'
";

   $cursor=$dbh->prepare($sql) or ErrorPage("$DBI::errstr");
   $cursor->execute;
   $yesno = $cursor->fetchrow_array;
   $cursor->finish;

   logit("   Returning value of $yesno for privilege");

   logit("Exit subroutine checkPriv");

   return($yesno);

}

sub refreshButton {

   logit("Enter subroutine refreshButton");

   return if $norefreshbutton;

   my $url		= "$scriptname?database=$database&user=$user&schema=$schema&object_type=$object_type&arg=$object_name";
   my $sid		= $query->param('sid') || "";
   my $serial		= $query->param('serial') || "";
   my $sortfield	= $query->param('sortfield') || "";
   my $username		= $query->param('username') || "";
   my $command		= $query->param('command') || "";

# Display refresh button

   print <<"EOF";
  <FORM METHOD="POST" ACTION="$scriptname">
    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
EOF
   print "<INPUT TYPE=HIDDEN NAME=database    VALUE=$database>\n" if $database;
   print "<INPUT TYPE=HIDDEN NAME=user        VALUE=$user>\n" if $user;
   print "<INPUT TYPE=HIDDEN NAME=schema      VALUE=$schema>\n" if $schema;
   print "<INPUT TYPE=HIDDEN NAME=object_type VALUE=$object_type>\n" if $object_type;
   print "<INPUT TYPE=HIDDEN NAME=arg         VALUE=$object_name>\n" if $object_name;
   print "<INPUT TYPE=HIDDEN NAME=url         VALUE=$url>\n" if $url;
   print "<INPUT TYPE=HIDDEN NAME=sid         VALUE=$sid>\n" if $sid;
   print "<INPUT TYPE=HIDDEN NAME=serial      VALUE=$serial>\n" if $serial;
   print "<INPUT TYPE=HIDDEN NAME=sortfield   VALUE=$sortfield>\n" if $sortfield;
   print "<INPUT TYPE=HIDDEN NAME=command     VALUE=$command>\n" if $command;
   print "<INPUT TYPE=HIDDEN NAME=username    VALUE=$username>\n" if $username;
   print "<INPUT TYPE=HIDDEN NAME=user        VALUE=$username>\n" if $username;
   print "<INPUT TYPE=SUBMIT NAME=sessions    VALUE=Refresh>\n";
   print "</FORM>\n";

   logit("Exit subroutine refreshButton");

}

sub topSessions {

   logit("Enter subroutine topSessions");

   my ($sql,$cursor,$sid,$serial,$username,$cpu,$command,$osuser,$status,$sprocess,$cprocess,$terminal,$program);
   my ($sortfield,$refreshrate,$highlight,$color,$blockchanges,$sqltext,$last_call_et,$logontime,$foo);
   my ($minutes,$seconds,$paddr,$sql1,$cursor1,$seconds_in_wait,$newsqltext,$sql_id,$sql_child_number);
   my ($altprocess,$moresql,$redlight,$lockwait,$orig_cellcolor);

   $sortfield		= $query->param('sortfield') || "status";
   $command		= $query->param('command') || "";
   $username		=  $query->param('username') || "";
   $refreshrate		= $ENV{'AUTO_REFRESH'} || "10";
   $highlight		= "#FFFFC6";
   $redlight		= "#DEBDDE";
   $orig_cellcolor	= $cellcolor;

   logit("   Sort field = $sortfield");

   unless ($norefreshbutton) {

      print <<"EOF";
  <FORM METHOD="POST" ACTION="$scriptname">
    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
    <INPUT TYPE=HIDDEN NAME=database    VALUE=$database>
    <INPUT TYPE=HIDDEN NAME=object_type VALUE=$object_type>
    <INPUT TYPE=HIDDEN NAME=arg         VALUE=$object_name>
    <INPUT TYPE=HIDDEN NAME=refreshrate VALUE=$refreshrate>
    <INPUT TYPE=HIDDEN NAME=sortfield   VALUE=$sortfield>
    <INPUT TYPE=HIDDEN NAME=username    VALUE=$username>
    <INPUT TYPE=SUBMIT NAME=foobar      VALUE=\"AutoRefresh ($refreshrate)\">
  </FORM>
  <P>
EOF

   }

   print << "EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
EOF
   if ($sortfield eq "sid") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=sid&command=$command&username=$username>SID</A></TH>\n";
   if ($sortfield eq "serial") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=serial&command=$command&username=$username>Serial#</A></TH>\n";
   if ($sortfield eq "waittime") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=waittime&command=$command&username=$username>Wait (sec)</A></TH>\n";
   if ($sortfield eq "orauser") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=orauser&command=$command&username=$username>Ora user</A></TH>\n";
   if ($sortfield eq "status") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=status&command=$command&username=$username>Status (mm:ss)</A></TH>\n";
#   if ($sortfield eq "sqltext") {
#      $color = $highlight;
#   } else {
#      $color = $headingcolor;
#   }
#   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=sqltext&command=$command&username=$username>SQL text</A></TH>\n";
   if ($sortfield eq "program") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=program&command=$command&username=$username>Program</A></TH>\n";
   if ($sortfield eq "osuser") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=osuser&command=$command&username=$username>OSuser</A></TH>\n";
   if ($sortfield eq "cpu") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=cpu&command=$command&username=$username>CPU</A></TH>\n";
   if ($sortfield eq "command") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=command&command=$command&username=$username>Commmand</A></TH>\n";
   if ($sortfield eq "blockchanges") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=blockchanges&command=$command&username=$username>Block changes</A></TH>\n";
   if ($sortfield eq "sprocess") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=sprocess&command=$command&username=$username>Server Process</A></TH>\n";
   if ($sortfield eq "cprocess") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=cprocess&command=$command&username=$username>Client Process</A></TH>\n";
   if ($sortfield eq "logontime") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=logontime&command=$command&username=$username>Logon time</A></TH>\n";
   if ($sortfield eq "terminal") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&arg=$object_name&sortfield=terminal&command=$command&username=$username>Terminal</A></TH>\n";

   $sortfield = "SID DESC"		if ($sortfield eq "sid");
   $sortfield = "SERIAL# DESC"		if ($sortfield eq "serial");
   $sortfield = "STATUS, SECONDS_IN_WAIT DESC"	if ($sortfield eq "waittime");
   $sortfield = "USERNAME"		if ($sortfield eq "orauser");
   $sortfield = "OSUSER"		if ($sortfield eq "osuser");
   $sortfield = "VALUE DESC"		if ($sortfield eq "cpu");
   $sortfield = "COMMAND DESC"		if ($sortfield eq "command");
   $sortfield = "BLOCK_CHANGES DESC"	if ($sortfield eq "blockchanges");
   $sortfield = "STATUS"		if ($sortfield eq "status");
   $sortfield = "SPROCESS DESC"		if ($sortfield eq "sprocess");
   $sortfield = "CPROCESS DESC"		if ($sortfield eq "cprocess");
#   $sortfield = "SQL_TEXT DESC"		if ($sortfield eq "sqltext");
   $sortfield = "LOGON_TIME DESC"	if ($sortfield eq "logontime");
   $sortfield = "TERMINAL"		if ($sortfield eq "terminal");
   $sortfield = "PROGRAM"		if ($sortfield eq "program");

   # Is a username passed?
   if ($username) {
      $moresql = "AND VS.USERNAME = '$username'";
   }

   if ($oracle9i || $oracle92) {

      $sql = "$copyright
SELECT
   VS.SID SID,
   VS.SERIAL# SERIAL#,
   VS.USERNAME USERNAME,
   VS.OSUSER OSUSER,
   VS.PROCESS CPROCESS,
   VS.PADDR,
   VSS.VALUE,
   DECODE(VS.COMMAND,
	'0','None',
	'1','Create table',
	'2','Insert',
	'3','Select',
	'4','Create cluster',
	'5','Alter cluster',
	'6','Update',
	'7','Delete',
	'8','Drop cluster',
	'9','Create index',
	'10','Drop index',
	'11','Alter index',
	'12','Drop table',
	'13','Create sequence',
	'14','Alter sequence',
	'15','Alter table',
	'16','Drop sequence',
	'17','Grant',
	'18','Revoke',
	'19','Create synonym',
	'20','Drop synonym',
	'21','Create view',
	'22','Drop view',
	'23','Validate index',
	'24','Create procedure',
	'25','Alter procedure',
	'26','Lock table',
	'27','No operation in progress',
	'28','Rename',
	'29','Comment',
	'30','Audit',
	'31','Noaudit',
	'32','Create database link',
	'33','Drop database link',
	'34','Create database',
	'35','Alter database',
	'36','Create rollback segment',
	'37','Alter rollback segment',
	'38','Drop rollback segment',
	'39','Create tablespace',
	'40','Alter tablespace',
	'41','Drop tablespace',
	'42','Alter session',
	'43','Alter user',
	'44','Commit',
	'45','Rollback',
	'46','Savepoint',
	'47','PL/SQL Execute',
	'48','Set transaction',
	'49','Alter system switch log',
	'50','Explain',
	'51','Create user',
	'52','Create role',
	'53','Drop user',
	'54','Drop role',
	'55','Set role',
	'56','Create schema',
	'57','Create control file',
	'58','Alter tracing',
	'59','Create trigger',
	'60','Alter trigger',
	'61','Drop trigger',
	'62','Analyze table',
	'63','Analyze index',
	'64','Analyze cluster',
	'65','Create profile',
	'66','Drop profile',
	'67','Alter profile',
	'68','Drop procedure',
	'69','Drop procedure',
	'70','Alter resource cost',
	'71','Create snapshot log',
	'72','Alter snapshot log',
	'73','Drop snapshot log',
	'74','Create snapshot',
	'75','Alter snapshot',
	'76','Drop snapshot',
	'79','Alter role',
	'85','Truncate table',
	'86','Truncate cluster',
	'88','Alter view',
	'91','Create function',
	'92','Alter function',
	'93','Drop function',
	'94','Create package',
	'95','Alter package',
	'96','Drop package',
	'97','Create package body',
	'98','Alter package body',
	'99','Drop package body') COMMAND,
   TO_CHAR(VSI.BLOCK_CHANGES,'999,999,999,999') BLOCK_CHANGES,
   VP.SPID SPROCESS,
   VS.STATUS STATUS,
   TO_CHAR(VS.LOGON_TIME,'Day MM/DD/YY HH24:MI:SS'),
   NVL(VS.TERMINAL,'Unknown'),
   VS.PROGRAM PROGRAM,
   VS.LAST_CALL_ET,
   VSW.SECONDS_IN_WAIT,
   VS.LOCKWAIT
FROM V\$SESSION VS,
     V\$SESS_IO VSI,
     V\$SESSTAT VSS,
     V\$SESSION_WAIT VSW,
     V\$PROCESS VP
WHERE VS.SID = VSI.SID
AND VS.SID = VSW.SID
AND VS.SID = VSS.SID
AND VSS.STATISTIC# = 12
AND VS.PADDR = VP.ADDR
AND VS.USERNAME IS NOT NULL
$moresql
   ORDER BY $sortfield
";
   }

   if ($oracle10 || $oracle11) {
   
      $sql = "$copyright
SELECT
   VS.SID SID,
   VS.SERIAL# SERIAL#,
   VS.USERNAME USERNAME,
   VS.OSUSER OSUSER,
   VS.PROCESS CPROCESS,
   VS.PADDR,
   VSS.VALUE,
   DECODE(VS.COMMAND,
	'0','None',
	'1','Create table',
	'2','Insert',
	'3','Select',
	'4','Create cluster',
	'5','Alter cluster',
	'6','Update',
	'7','Delete',
	'8','Drop cluster',
	'9','Create index',
	'10','Drop index',
	'11','Alter index',
	'12','Drop table',
	'13','Create sequence',
	'14','Alter sequence',
	'15','Alter table',
	'16','Drop sequence',
	'17','Grant',
	'18','Revoke',
	'19','Create synonym',
	'20','Drop synonym',
	'21','Create view',
	'22','Drop view',
	'23','Validate index',
	'24','Create procedure',
	'25','Alter procedure',
	'26','Lock table',
	'27','No operation in progress',
	'28','Rename',
	'29','Comment',
	'30','Audit',
	'31','Noaudit',
	'32','Create database link',
	'33','Drop database link',
	'34','Create database',
	'35','Alter database',
	'36','Create rollback segment',
	'37','Alter rollback segment',
	'38','Drop rollback segment',
	'39','Create tablespace',
	'40','Alter tablespace',
	'41','Drop tablespace',
	'42','Alter session',
	'43','Alter user',
	'44','Commit',
	'45','Rollback',
	'46','Savepoint',
	'47','PL/SQL Execute',
	'48','Set transaction',
	'49','Alter system switch log',
	'50','Explain',
	'51','Create user',
	'52','Create role',
	'53','Drop user',
	'54','Drop role',
	'55','Set role',
	'56','Create schema',
	'57','Create control file',
	'58','Alter tracing',
	'59','Create trigger',
	'60','Alter trigger',
	'61','Drop trigger',
	'62','Analyze table',
	'63','Analyze index',
	'64','Analyze cluster',
	'65','Create profile',
	'66','Drop profile',
	'67','Alter profile',
	'68','Drop procedure',
	'69','Drop procedure',
	'70','Alter resource cost',
	'71','Create snapshot log',
	'72','Alter snapshot log',
	'73','Drop snapshot log',
	'74','Create snapshot',
	'75','Alter snapshot',
	'76','Drop snapshot',
	'79','Alter role',
	'85','Truncate table',
	'86','Truncate cluster',
	'88','Alter view',
	'91','Create function',
	'92','Alter function',
	'93','Drop function',
	'94','Create package',
	'95','Alter package',
	'96','Drop package',
	'97','Create package body',
	'98','Alter package body',
	'99','Drop package body') COMMAND,
   TO_CHAR(VSI.BLOCK_CHANGES,'999,999,999,999') BLOCK_CHANGES,
   VP.SPID SPROCESS,
   VS.STATUS STATUS,
   TO_CHAR(VS.LOGON_TIME,'Day MM/DD/YY HH24:MI:SS'),
   NVL(VS.TERMINAL,'Unknown'),
   VS.PROGRAM PROGRAM,
   VS.LAST_CALL_ET,
   VSW.SECONDS_IN_WAIT,
   VS.SQL_ID,
   VS.SQL_CHILD_NUMBER,
   VS.LOCKWAIT
FROM V\$SESSION VS,
     V\$SESS_IO VSI,
     V\$SESSTAT VSS,
     V\$SESSION_WAIT VSW,
     V\$PROCESS VP
WHERE VS.SID = VSI.SID
AND VS.SID = VSW.SID
AND VS.SID = VSS.SID
AND VSS.STATISTIC# = 12
AND VS.PADDR = VP.ADDR
AND VS.USERNAME IS NOT NULL
$moresql
   ORDER BY $sortfield
";
   }

   logit("SQL = $sql");

   $cursor = $dbh->prepare($sql);
   logit("$DBI::errstr");
   $cursor->execute;
   while (($sid,$serial,$username,$osuser,$cprocess,$paddr,$cpu,$command,$blockchanges,$sprocess,$status,$logontime,$terminal,$program,$last_call_et,$seconds_in_wait,$sql_id,$sql_child_number,$lockwait) = $cursor->fetchrow_array) {

      $sid		= "&nbsp" unless $sid;
      $serial		= "&nbsp" unless $serial;
      $username		= "&nbsp" unless $username;
      $osuser		= "&nbsp" unless $osuser;
      $cpu		= "&nbsp" unless $cpu;
      $command		= "&nbsp" unless $command;
      $blockchanges	= "&nbsp" unless $blockchanges;
      $status		= "&nbsp" unless $status;
      $cprocess		= "&nbsp" unless $cprocess;
         # Why does Oracle show the pid as 1234 if it can't find it?
         $cprocess	= "n/a" if ($cprocess eq "1234");
      $sprocess		= "&nbsp" unless $sprocess;
#      $sqltext		= "&nbsp" unless $sqltext;
      $logontime	= "&nbsp" unless $logontime;
      $terminal		= "&nbsp" unless $terminal;
      $program		= "&nbsp" unless $program;
      $seconds_in_wait	= "0" unless $seconds_in_wait;
      $minutes		= int($last_call_et / 60);
      $seconds		= $last_call_et % 60;
      $seconds		= "0$seconds" if (length($seconds) == 1);
      $last_call_et	= "($minutes:$seconds)";
      # Highlight the row in red if it is being blocked by another session
      if ($lockwait) {
         $cellcolor = $redlight;
      } else {
         $cellcolor = $orig_cellcolor;
      }
      print "<TR><TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=SESSIONINFO&user=$username&sid=$sid&serial=$serial>$sid</A></TD>\n";
      print "<TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$serial</TD>\n";
      print "<TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$seconds_in_wait</TD>\n";
      print "<TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=TOPSESSIONS&username=$username>$username</A></TD>\n";
      print "<TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$status&nbsp;$last_call_et</TD>\n";
      print "<TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$program</TD>\n";
      print "<TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$osuser</TD>\n";
      print "<TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$cpu</TD>\n";
      print "<TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$command</TD>\n";
      print "<TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$blockchanges</TD>\n";
      print "<TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$sprocess</TD>\n";
      print "<TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$cprocess</TD>\n";
      print "<TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$logontime</TD>\n";
      print "<TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$terminal</TD></TR>\n";
   }
   $cursor->finish;
   print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF

   logit("Exit subroutine topSessions");

}
      
sub SQLareaCount {

   logit("Enter subroutine SQLareaCount");

   my ($sql,$text,$link,$infotext);

   my $sqltext = $query->param('sqltext');

   text("SQL: $sqltext ...");

   # Fix single quotes
   $sqltext =~ s/'/''/g;

   logit("   SQL passed: $sqltext");

   $sql = "
SELECT 
   TO_CHAR(SUM(EXECUTIONS),'999,999,999,999')		\"Executions #\"
FROM V\$SQLAREA
   WHERE SQL_TEXT LIKE '$sqltext%'
"; 

   $text = "Sum of exection count for all SQL statements in V\$SQLAREA which are LIKE the sql passed.";
   $link = "";
   $infotext = "There is no SQL in V\$SQLAREA which is LIKE the sql passed.";
   DisplayTable($sql,$text,$link,$infotext);

   $sql = "
SELECT 
   EXECUTIONS		\"Executions #\",
   SQL_TEXT		\"SQL text\"
FROM V\$SQLAREA
   WHERE SQL_TEXT LIKE '$sqltext%'
"; 

   $text = "Execution count for individual statements in V\$SQLAREA which are LIKE the sql passed.";
   $link = "";
   $infotext = "There is no SQL in V\$SQLAREA which is LIKE the sql passed.";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine SQLareaCount");

   Footer();
   exit;

}

sub sqlInfo  {

   # Explain plan / statistics etc. 

   logit("Enter subroutine sqlInfo");

   my $sql_id = $query->param('arg');

   my ($sql,$text,$link,$infotext);
   my ($cursor,$line);

   logit("   Collecting info for SQL ID $sql_id");

   $sql = "Alter session set statistics_level = 'ALL'";
   $dbh->do($sql);

   my $size		= $fontsize + 1;

   #print "<pre>";
   print <<"EOF";
<table border=0 bgcolor='$bordercolor' cellpadding=1 cellspacing=0>
  <tr>
    <td width=100%>
      <table border=0 cellpadding=2 cellspacing=1>
        <tr>
          <td bgcolor='$cellcolor'>
            <font color='$fontcolor' size='$size' face='$font'>
            </center>
            <pre>
EOF
   
   $sql = "Select * from table( dbms_xplan.display_cursor('$sql_id',0,'ALL IOSTATS'))";
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   while ($line = $cursor->fetchrow_array) {
      print "$line<br>";
   }
   $cursor->finish;

   print <<"EOF";
            </pre>
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>
EOF

   #print "</pre>";

   #$text = "Foo";
   #$infotext = "No info";
   #DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine sqlInfo");

}

sub sessionInfo {

   logit("Enter subroutine sessionInfo");
   logit("   Username connected to database is $username");

   my $sid	= $query->param('sid')		|| "";
   my $serial	= $query->param('serial')	|| "";
   my $username	= $query->param('username')	|| "";
   my $click	= $query->param('click')	|| "";
   my $page	= $query->param('page')		|| "general" ;
   my $refreshrate	= 5;

   my ($sql,$cursor,$hours,$minutes,$seconds,$text,$link,$infotext,$sqltext,$piece,$count,$filename,$object_name,$owner,$object_string);
   my ($blocking_session_string,$current_sql_string,$prev_sql_string,$sql_trace_string,$killstring);

   my ($saddr, $paddr, $user, $command, $ownerid, $taddr, $lockwait, $status, $server, $schema, $schemaname, $osuser, $cprocess, $sprocess, $machine, $terminal, $program, $type, $sql_address, $sql_hash_value, $sql_id, $sql_child_number, $prev_sql_addr, $prev_hash_value, $prev_sql_id, $prev_child_number, $module, $action, $client_info, $row_wait_obj, $row_wait_file, $row_wait_block, $row_wait_row, $logon_time, $last_call_et, $resource_consumer_group, $client_identifier, $blocking_session_status, $blocking_instance, $blocking_session, $event, $p1text, $p1, $p1raw, $p2text, $p2, $p2raw, $p3text, $p3, $p3raw, $wait_class_id, $wait_class, $wait_time, $seconds_in_wait, $state, $service_name, $sql_trace, $sql_trace_waits, $sql_trace_binds);

#      print <<"EOF";
#  <FORM METHOD="POST" ACTION="$scriptname">
#    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
#    <INPUT TYPE=HIDDEN NAME=database    VALUE=$database>
#    <INPUT TYPE=HIDDEN NAME=object_type VALUE=$object_type>
#    <INPUT TYPE=HIDDEN NAME=arg         VALUE=$object_name>
#    <INPUT TYPE=HIDDEN NAME=sid         VALUE=$sid>
#    <INPUT TYPE=HIDDEN NAME=username	VALUE=$username>
#    <INPUT TYPE=HIDDEN NAME=refreshrate VALUE=$refreshrate>
#    <INPUT TYPE=HIDDEN NAME=page	VALUE=$page>
#    <INPUT TYPE=SUBMIT NAME=foobar      VALUE=\"AutoRefresh ($refreshrate)\">
#  </FORM>
#  <P>
#EOF

    $killstring = "<a href=$scriptname?database=$database&object_type=SESSIONINFO&page=killsession&sid=$sid&serial=$serial&click=first><b>Kill this session</b><br>";

   if ($page eq "killsession") {

      # Is it the first click for the kill, or the second?
      if ($click eq "first") {
         $killstring = "<a href=$scriptname?database=$database&object_type=SESSIONINFO&page=killsession&sid=$sid&serial=$serial&click=last><b>Once more to kill session</b><br>";
         $page = "general";
      }
      if ($click eq "last") {
         $sql = "Alter system kill session '$sid,$serial'";
         doSQL($dbh,$sql);
         $object_type	= "TOPSESSIONS";
         topSessions();
         footer();
      }
   }

   refreshButton();

print <<"EOF";

   <table width=50% align=center>
     <tr>
       <td align=left><a href=$scriptname?database=$database&object_type=SESSIONINFO&sid=$sid&page=general>General</a></td>
       <td align=center><a href=$scriptname?database=$database&object_type=SESSIONINFO&sid=$sid&page=waithistory>Waits</a></td>
       <td align=right><a href=$scriptname?database=$database&object_type=SESSIONINFO&sid=$sid&page=cursors>Open Cursors</a></td>
     </tr>
     <tr>
       <td align=left colspan=3><a href=$scriptname?database=$database&object_type=TOPSESSIONS>Session list</a></td>
     </tr>
   </table>

   <hr width=50%>
EOF

   if ($page eq "waithistory") {

      $sql = "
Select seq# \"Sequence\", event \"Event\", p1text \"p1 text\", p1 \"p1\", p2text \"p2\", p2, p3text \"p3 text\", p3 \"p3\", wait_time \"Wait time\", wait_count \"Wait count\" from v\$session_wait_history where sid=$sid order by seq#";

      $text = "Wait history for session ID $sid.";
      #$link = "$scriptname?database=$database&object_type=SQLINFO";
      $link = "";
      $infotext = "";
      DisplayTable($sql,$text,$link,$infotext);

   }

   if ($page eq "cursors") {

      $sql = "
Select distinct sql_id \"SQL ID\", sql_text \"SQL Text\", count(*) \"Count\" from v\$open_cursor where sid=$sid group by sql_id, sql_text order by 3 desc
";

      $text = "Open cursors  / statement count for session ID $sid.";
      $link = "$scriptname?database=$database&object_type=SQLINFO";
      $infotext = "There are no open cursors for this session.";
      DisplayTable($sql,$text,$link,$infotext);

   }

   if ($page eq "general") {

      if ($oracle9i || $oracle92) {

         $sql = "
Select saddr, serial#, paddr, user#, username, command, ownerid, taddr, lockwait, status, server, schema#, schemaname, osuser, process, machine, nvl(terminal,'unknown'), program, type, sql_address, sql_hash_value, module, action, nvl(client_info,'unknown'), row_wait_obj#, row_wait_file#, row_wait_block#, row_wait_row#, to_char(logon_time,'Day Mon DD YYYY HH24:MI:SS'), last_call_et, resource_consumer_group, nvl(client_identifier,'unknown') from v\$session where sid = $sid";

         $cursor = $dbh->prepare($sql) || print "$DBI::errstr";
         $cursor->execute;
         ($saddr, $serial, $paddr, $user, $username, $command, $ownerid, $taddr, $lockwait, $status, $server, $schema, $schemaname, $osuser, $cprocess, $machine, $terminal, $program, $type, $sql_address, $sql_hash_value, $module, $action, $client_info, $row_wait_obj, $row_wait_file, $row_wait_block, $row_wait_row, $logon_time, $last_call_et, $resource_consumer_group, $client_identifier) = $cursor->fetchrow_array;
         $cursor->finish;

      }

      if ($oracle10 || $oracle11) {

         $sql = "
Select saddr, serial#, paddr, user#, username, command, ownerid, taddr, lockwait, status, server, schema#, schemaname, osuser, process, machine, nvl(terminal,'unknown'), program, type, sql_address, sql_hash_value, sql_id, sql_child_number, prev_sql_addr, prev_hash_value, prev_sql_id, prev_child_number, module, action, nvl(client_info,'unknown'), row_wait_obj#, row_wait_file#, row_wait_block#, row_wait_row#, to_char(logon_time,'Day Mon DD YYYY HH24:MI:SS'), last_call_et, resource_consumer_group, nvl(client_identifier,'unknown'), blocking_session_status, blocking_instance, blocking_session, event, p1text, p1, p1raw, p2text, p2, p2raw, p3text, p3, p3raw, wait_class_id, wait_class, wait_time, seconds_in_wait, state, service_name, sql_trace, sql_trace_waits, sql_trace_binds from v\$session where sid = $sid";

         $cursor = $dbh->prepare($sql) || print "$DBI::errstr";
         $cursor->execute;
         ($saddr, $serial, $paddr, $user, $username, $command, $ownerid, $taddr, $lockwait, $status, $server, $schema, $schemaname, $osuser, $cprocess, $machine, $terminal, $program, $type, $sql_address, $sql_hash_value, $sql_id, $sql_child_number, $prev_sql_addr, $prev_hash_value, $prev_sql_id, $prev_child_number, $module, $action, $client_info, $row_wait_obj, $row_wait_file, $row_wait_block, $row_wait_row, $logon_time, $last_call_et, $resource_consumer_group, $client_identifier, $blocking_session_status, $blocking_instance, $blocking_session, $event, $p1text, $p1, $p1raw, $p2text, $p2, $p2raw, $p3text, $p3, $p3raw, $wait_class_id, $wait_class, $wait_time, $seconds_in_wait, $state, $service_name, $sql_trace, $sql_trace_waits, $sql_trace_binds) = $cursor->fetchrow_array;
         $cursor->finish;

      }

      $sql = "Select spid from v\$process where addr = '$paddr'";
      $cursor = $dbh->prepare($sql) || print "$DBI::errstr";
      $cursor->execute;
      $sprocess = $cursor->fetchrow_array;
      $cursor->finish;

      # Set up the string for SQL_ID
      if ($sql_id) {
         $current_sql_string = "<a href=$scriptname?database=$database&object_type=SQLINFO&arg=$sql_id><b>$sql_id</b></a>";
      } else {
         $current_sql_string = "<b>n/a</b>";
      }

      # If the current SQL ID and the previous sql ID are the same,
      # let's not repeat ourselves. That's if prev_sql_id is even set.
      if (($prev_sql_id) && ($prev_sql_id ne $sql_id)) {
         $prev_sql_string = "<a href=$scriptname?database=$database&object_type=SQLINFO&arg=$prev_sql_id><b>$prev_sql_id</b></a>";
      } else {
         $prev_sql_string = "<b>n/a</b>";
      }

      # Set up a url for enabling or disabling trace
      if ($sql_trace eq "ENABLED") {
         $sql_trace_string = "<a href=$scriptname?database=$database&object_type=TRACESESSION&sid=$sid&serial=$serial&trace=disable><b>$sql_trace</b></a>";
      } else {
          $sql_trace_string = "<a href=$scriptname?database=$database&object_type=TRACESESSION&sid=$sid&serial=$serial&trace=enable><b>$sql_trace</b></a>"; 
      }

      # Why does Oracle show "1234" when it doesn't know the client process ID?
      # Let's fix it.
      if ($cprocess eq "1234") {
         $cprocess = "n/a";
      }

      # Calculate last_call_et into minutes / seconds
      # Need to add hours / days etc.
      $minutes          = int($last_call_et / 60);
      $seconds          = $last_call_et % 60;
      $seconds          = "0$seconds" if (length($seconds) == 1);
      $last_call_et     = "$minutes minutes $seconds seconds";

      # Calculate seconds_in_wait into minutes / seconds
      # Need to add hours / days etc.
      $minutes          = int($seconds_in_wait / 60);
      $seconds          = $seconds_in_wait % 60;
      $seconds          = "0$seconds" if (length($seconds) == 1);
      $seconds_in_wait  = "$minutes minutes $seconds seconds";

#      if ($blocking_session) {
#         $blocking_session_string = "<a href=$scriptname?database=$database&object_type=SESSIONINFO&sid=$blocking_session><b>$blocking_session</b></a>";
#         # Get some info about what object we're waiting for (if we're waiting)
#         $sql = "Select name from v\$datafile where file# = $row_wait_file";
#         $cursor = $dbh->prepare($sql);
#         $cursor->execute;
#         $filename = $cursor->fetchrow_array;
#         $cursor->finish;
#         $sql = "Select object_name, object_type, owner from dba_objects where object_id = $row_wait_obj";
#         $cursor = $dbh->prepare($sql);
#         $cursor->execute;
#         ($object_name,$object_type,$owner) = $cursor->fetchrow_array;
#         $cursor->finish;
#         $object_string = "($object_type) $owner.$object_name";
#      } else {
#         $blocking_session_string = "<b>None</b>";
#         $filename = "<b>n/a</b>";
#         $object_string = "<b>n/a</b>";
#      }

      if ($blocking_session) {
         $blocking_session_string = "<a href=$scriptname?database=$database&object_type=SESSIONINFO&sid=$blocking_session><b>$blocking_session</b></a>";
      } else {
         $blocking_session_string = "<b>None</b>";
      }
      # Get some info about what object we're waiting for (if we're waiting)
      $sql = "Select name from v\$datafile where file# = $row_wait_file";
      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      $filename = $cursor->fetchrow_array;
      $cursor->finish;
      $sql = "Select object_name, object_type, owner from dba_objects where object_id = $row_wait_obj";
      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      ($object_name,$object_type,$owner) = $cursor->fetchrow_array;
      $cursor->finish;
      # Make $filename an href if it's defined.
      $filename = "<a href=$scriptname?database=$database&object_type=DATAFILE&arg=$filename><b>$filename</b></a>" if $filename;
      $object_string = "<a href=$scriptname?database=$database&object_type=$object_type&schema=$owner&arg=$object_name><b>($object_type) $owner.$object_name</b></a>" if ($object_name && $object_type && $owner);
      unless ($filename && $object_name && $object_type && $owner && $status eq "ACTIVE") {
         $filename = "<b>n/a</b>";
         $object_string = "<b>n/a</b>";
      }

      print <<"EOF";
<table width=100% align=center>
  <tr>

   <!-- Column 1 - Server -->   

    <td valign=top><font color='$fontcolor' size='$fontsize' face='$font'>
<b><em>Server</em></b>
      <table>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      DB User Name<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <a href=$scriptname?database=$database&schema=$username&object_type=USERINFO><b>$username</b></a>
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      Server Process ID<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$sprocess</b>
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      Current status<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$status</b>
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      SID<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$sid</b>
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      Serial Number<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$serial</b>
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      Logged on<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$logon_time</b>
          </td>
        </tr>
      </table>
    </td>

   <!-- Column 2 - Client -->   

    <td valign=top><font color='$fontcolor' size='$fontsize' face='$font'>
<b><em>Client</em></b>
      <table>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      OS User Name<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$osuser</b>
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      Client Process ID<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$cprocess</b>
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      Hostname<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$hostname</b>
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      Terminal<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$terminal</b>
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      Client id<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$client_identifier</b>
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      Client info<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$client_info</b>
          </td>
        </tr>
      </table>
    </td>

   <!-- Column 3 - Application -->   

    <td valign=top><font color='$fontcolor' size='$fontsize' face='$font'>
<b><em>Application</em></b>
      <table>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      Current SQL<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      $current_sql_string
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      Previous SQL<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      $prev_sql_string
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      Last Call ET<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$last_call_et</b>
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      SQL Trace<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$sql_trace_string</b>
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      Program<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$program</b>
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      Module<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$module</b>
          </td>
        </tr>
      </table>
    </td>
  </tr>

  <tr>

   <!-- Column 1 - Contention info -->   

    <td valign=top><font color='$fontcolor' size='$fontsize' face='$font'>
<b><em>Contention / Object info</em></b>
      <table>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      Blocking session ID<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      $blocking_session_string
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      File name<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$filename</b>
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      Waiting on<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$object_string</b>
          </td>
        </tr>
      </table>
    </td>

   <!-- Column 2 - Wait info -->   

    <td valign=top><font color='$fontcolor' size='$fontsize' face='$font'>
<b><em>Wait info</em></b>
      <table>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      Current wait event<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$event</b>
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      Wait class<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$wait_class</b>
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      Waiting for<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$seconds_in_wait</b>
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      p1<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$p1text $p1</b>
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      p2<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$p2text $p2</b>
          </td>
        </tr>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      p3<br>
          </td>
          <td align=left><font color='$fontcolor' size='$fontsize' face='$font'>
      <b>$p3text $p3</b>
          </td>
        </tr>
      </table>
    </td>

   <!-- Column 3 - Admin -->   

    <td valign=top><font color='$fontcolor' size='$fontsize' face='$font'>
<b><em>Administration</em></b>
      <table>
        <tr>
          <td align=right><font color='$fontcolor' size='$fontsize' face='$font'>
      $killstring
          </td>
        </tr>
      </table>
    </td>

  </tr>
</table>
<hr width=50%>
EOF



      # It's better to take the SQL from V$SQLTEXT because it shows all of the SQL, where
      # V$OPEN_CURSOR does not. Unfortunately, sometime V$OPEN_CURSOR is populated, and
      # V$SQLTEXT is not. I don't know the criteria for this. 
      $count = recordCount($dbh,"Select piece from v\$sqltext where sql_id = '$sql_id'");
      if ($count > 0) { 

         logit("Taking SQL from SQLTEXT");
         $sql = "Select sql_text from v\$sqltext where sql_id = '$sql_id' order by piece";
         $cursor = $dbh->prepare($sql);
         $cursor->execute;
         while ($piece = $cursor->fetchrow_array) {
            $sqltext = "$sqltext$piece";
         }
         $cursor->finish;

      } else {

         logit("Taking SQL from OPEN_CURSOR");
         $sql = "Select distinct sql_id, sql_text from v\$open_cursor where sql_id = '$sql_id'";
         $cursor = $dbh->prepare($sql);
         $cursor->execute;
         $sqltext = $cursor->fetchrow_array;
         $cursor->finish;
         
      }

      logit("SQL : $sqltext");

      if ($sqltext ne "") {

         message("Current SQL for session $sid");

         #my $size = $fontsize+1;

         print <<"EOF";
<table align=center>
  <tr>
    <td><font color='$fontcolor' size='$fontsize' face='$font'>
$sqltext
    </td>
  </tr>
</table>
EOF

      }


#         print <<"EOF";
#<table border=0 bgcolor='$bordercolor' cellpadding=1 cellspacing=0>
#  <tr>
#    <td width=100%>
#      <table border=0 cellpadding=2 cellspacing=1>
#        <tr>
#          <td bgcolor='$cellcolor'>
#            <font color='$fontcolor' size='$size' face='$font'>
#            </center>
#            <pre>
#$sqltext
#            </pre>
#          </td>
#        </tr>
#      </table>
#    </td>
#  </tr>
#</table>
#EOF

#    my $highlightcolor = "#ffffc6";

#   print << "EOF";
#<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
#  <TR>
#    <TD WIDTH=100%>
#      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
#        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>&nbsp;</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>SID</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Serial#</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Server pid</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Status</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Username</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Logon</TH>
#        <TR>
#          <TD BGCOLOR='$highlightcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><b>Server</b></TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$sid</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$serial</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$sprocess</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$status</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$username</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$logon_time</TD>
#        </TR>
#        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>&nbsp;</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>OS User</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Hostname</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Client pid</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Terminal</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Client ID</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Client Info</TH>
#        <TR>
#          <TD BGCOLOR='$highlightcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><b>Client</b></TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$osuser</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$hostname</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$cprocess</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$terminal</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$client_identifier</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$client_info</TD>
#        </TR>
#        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>&nbsp;</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Current SQL</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Prev SQL</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Last Call ET</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>SQL Trace</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Program</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Module</TH>
#        <TR>
#          <TD BGCOLOR='$highlightcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><b>Application</b></TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$current_sql_string</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$prev_sql_string</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$last_call_et</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$sql_trace</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$program</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$module</TD>
#        </TR>
#        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>&nbsp;</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Current wait event</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Wait class</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Wait duration</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>p1</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>p2</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>p3</TH>
#        <TR>
#          <TD BGCOLOR='$highlightcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><b>Wait info</b></TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$event</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$wait_class</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$seconds_in_wait</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$p1text $p1</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$p2text $p2</TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$p3text $p3</TD>
#        </TR>
#        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>&nbsp;</TH>
#        <TH BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Blocking session ID</TH>
#        <TH COLSPAN=2 BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Waiting on</TH>
#        <TH COLSPAN=3 BGCOLOR='$highlightcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>File name</TH>
#        <TR>
#          <TD BGCOLOR='$highlightcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><b>Contention</b></TD>
#          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$blocking_session_string</TD>
#          <TD COLSPAN=2 BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$object_string</TD>
#          <TD COLSPAN=3 BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$filename</TD>
#        </TR>
#      </TABLE>
#    </TD>
#  </TR>
#</TABLE>
#EOF

   }

   logit("Exit subroutine sessionInfo");

}


sub showSessions {

   logit("Enter subroutine showSessions");
   logit("   Username connected to database is $username");

# Instance session information

   my ($sql,$text,$cursor,$numfields,@row,$counter1,$counter2,$count,$paddr);
   my (@username,@osuser,@sid,@serial,@status,@process,@program,@command);
   my (@address,@hash_value,@rows_processed,@logon_time,@sqltext,$altersystem);
   my ($mysid,$sessions,$sid,$serial,$user,$moresql,$all,$listing,$listsql);
   my ($link,$infotext,$showwaitinfo,$event,@sql_trace,$value,$trace);

   $user	= shift;
   $sid		= $query->param('sid') || "";
   $serial	= $query->param('serial') || "";
   $listing	= $query->param('listing') || "all";

# Find out if the connected user has the "ALTER SYSTEM" privilege.
# This has nothing to do with the above $user variable.

   $altersystem = checkPriv("ALTER SYSTEM");

   refreshButton();
  
   print "<P></CENTER>\n";

# If user is not "%", then count the number of sessions
# and show a message if there is none.

   if ( $user ne "%" ) {
      $sql = "$copyright
SELECT COUNT(*) FROM V\$SESSION
   WHERE USERNAME = '$user'
";
      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      $count = $cursor->fetchrow_array;
      $cursor->finish;
      if ( $count == 0 ) {
         message("$user has no sessions in this instance.");
         Footer();
         exit;
      }
    } else {
#      DisplayGraph("sessions","","Active and inactive session history");
   }

# Decide which type of session to show based on $listing (ALL,ACTIVE,INACTIVE)

   if ($listing eq "all") {
      $listsql = "";
      logit("  Displaying all sessions.");
   }
   if ($listing eq "active") {
      $listsql = "AND S.STATUS = 'ACTIVE'";
      logit("  Displaying only ACTIVE sessions.");
   }
   if ($listing eq "inactive") {
      $listsql = "AND S.STATUS != 'ACTIVE'";
      logit("  Displaying only sessions which are not ACTIVE.");
   }

# If a sid and serial# is passed, create the SQL to select only that session.

   if ($sid && $serial) {
      $moresql = "AND S.SID = $sid AND S.SERIAL# = $serial\n";
      $showwaitinfo = "Yep";
   } else {
      $moresql = "";
   }

# Get my SID

   $sql = "$copyright
SELECT DISTINCT SID FROM V\$MYSTAT
";
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $mysid = $cursor->fetchrow_array;
   $cursor->finish;

   $sql = "$copyright
SELECT DISTINCT
   S.USERNAME,
   S.OSUSER,
   S.SID,
   S.SERIAL#,
   S.STATUS,
   VP.SPID,
   S.PROGRAM,
   S.SQL_TRACE,
   DECODE(S.COMMAND,
	'0','No command in progress',
	'1','Create table',
	'2','Insert',
	'3','Select',
	'4','Create cluster',
	'5','Alter cluster',
	'6','Update',
	'7','Delete',
	'8','Drop cluster',
	'9','Create index',
	'10','Drop index',
	'11','Alter index',
	'12','Drop table',
	'13','Create sequence',
	'14','Alter sequence',
	'15','Alter table',
	'16','Drop sequence',
	'17','Grant',
	'18','Revoke',
	'19','Create synonym',
	'20','Drop synonym',
	'21','Create view',
	'22','Drop view',
	'23','Validate index',
	'24','Create procedure',
	'25','Alter procedure',
	'26','Lock table',
	'27','No operation in progress',
	'28','Rename',
	'29','Comment',
	'30','Audit',
	'31','Noaudit',
	'32','Create database link',
	'33','Drop database link',
	'34','Create database',
	'35','Alter database',
	'36','Create rollback segment',
	'37','Alter rollback segment',
	'38','Drop rollback segment',
	'39','Create tablespace',
	'40','Alter tablespace',
	'41','Drop tablespace',
	'42','Alter session',
	'43','Alter user',
	'44','Commit',
	'45','Rollback',
	'46','Savepoint',
	'47','PL/SQL Execute',
	'48','Set transaction',
	'49','Alter system switch log',
	'50','Explain',
	'51','Create user',
	'52','Create role',
	'53','Drop user',
	'54','Drop role',
	'55','Set role',
	'56','Create schema',
	'57','Create control file',
	'58','Alter tracing',
	'59','Create trigger',
	'60','Alter trigger',
	'61','Drop trigger',
	'62','Analyze table',
	'63','Analyze index',
	'64','Analyze cluster',
	'65','Create profile',
	'66','Drop profile',
	'67','Alter profile',
	'68','Drop procedure',
	'69','Drop procedure',
	'70','Alter resource cost',
	'71','Create snapshot log',
	'72','Alter snapshot log',
	'73','Drop snapshot log',
	'74','Create snapshot',
	'75','Alter snapshot',
	'76','Drop snapshot',
	'79','Alter role',
	'85','Truncate table',
	'86','Truncate cluster',
	'88','Alter view',
	'91','Create function',
	'92','Alter function',
	'93','Drop function',
	'94','Create package',
	'95','Alter package',
	'96','Drop package',
	'97','Create package body',
	'98','Alter package body',
	'99','Drop package body'),
   TO_CHAR(S.LOGON_TIME,'Day MM/DD/YY HH24:MI'),
   T.ADDRESS,
   T.HASH_VALUE,
   MAX(Q.ROWS_PROCESSED)
FROM V\$SESSION S, V\$SQLTEXT T, V\$SQL Q, V\$PROCESS VP
   WHERE S.USERNAME IS NOT NULL 
   $listsql
   AND S.USERNAME LIKE '$user'
   AND S.SQL_ADDRESS = T.ADDRESS(+) 
   AND S.SQL_ADDRESS = Q.ADDRESS(+)
   AND S.SQL_HASH_VALUE = T.HASH_VALUE(+)
   AND S.SQL_HASH_VALUE = Q.HASH_VALUE(+)
   AND S.PADDR = VP.ADDR
   AND S.SID != $mysid
   $moresql
GROUP BY S.USERNAME, S.OSUSER, S.SID, S.SERIAL#, S.STATUS, VP.SPID, S.PROGRAM, S.SQL_TRACE, S.COMMAND, S.LOGON_TIME, T.ADDRESS, T.HASH_VALUE
ORDER BY S.STATUS
";

   logit("SQL: $sql");
   $cursor = $dbh->prepare($sql);
   print $DBI::errstr unless ($cursor);
   $cursor->execute;
   $numfields = $cursor->{NUM_OF_FIELDS};
   $counter1=0;
   while (@row = $cursor->fetchrow_array) {
      $sessions++;
      $username[$counter1]		= $row[0] or $username[$counter1] = "&nbspc;";
      $osuser[$counter1]		= $row[1] or $osuser[$counter1] = "Unknown";
      $sid[$counter1]			= $row[2] or $sid[$counter1] = "&nbsp;";
      $serial[$counter1]		= $row[3] or $serial[$counter1] = "&nbsp;";
      $status[$counter1]		= $row[4] or $status[$counter1] = "&nbsp;";
      $process[$counter1]		= $row[5] or $process[$counter1] = "Unknown";
      $program[$counter1]		= $row[6] or $program[$counter1] = "Unknown";
      $sql_trace[$counter1]		= $row[7] or $sql_trace[$counter1] = "Unknown";
      $command[$counter1]		= $row[8] or $command[$counter1] = "Unknown";
      $logon_time[$counter1]		= $row[9] or $logon_time[$counter1] = "Unknown"; 
      $address[$counter1]		= $row[10] or $address[$counter1] = "&nbsp;";
      $hash_value[$counter1]		= $row[11] or $hash_value[$counter1] = "&nbsp;";
      $rows_processed[$counter1]	= $row[12] or $rows_processed[$counter1] = "None";
      $counter1++;
   }
   $cursor->finish;

   $counter2 = 0;

   foreach (@address) {
      $sql = "$copyright
SELECT 
   SQL_TEXT, 
   PIECE 
FROM V\$SQLTEXT 
   WHERE ADDRESS = ?
   ORDER BY PIECE
";
   $cursor = $dbh->prepare($sql);
   $cursor->bind_param(1,$address[$counter2]);
   $cursor->execute;
   while (@row = $cursor->fetchrow_array) {
      $sqltext[$counter2] = "$sqltext[$counter2]$row[0]";
    }
   $cursor->finish;

# Fix the SQL so it displays in HTML format correctly

   $sqltext[$counter2] =~ s/"/&quot;/g;
   $sqltext[$counter2] =~ s/>/&gt;/g;
   $sqltext[$counter2] =~ s/</&lt;/g;

# If displaying a single session, show the session wait info..
   
   if ($showwaitinfo) {

      $sql = "$copyright
SELECT 
   SEQ#							\"Seq#\",
   EVENT						\"Event\",
   SECONDS_IN_WAIT					\"Seconds waiting\"
FROM V\$SESSION_WAIT
   WHERE SID = $sid[$counter2]
";
  
      $text = "Current session wait information.";
      $link = "";
      $infotext = "No info in V\$SESSION_WAIT.";
      print "<CENTER>\n";
      DisplayTable($sql,$text,$link,$infotext);
      print "</CENTER><BR>\n";

      $sql = "
SELECT
   EVENT
FROM V\$SESSION_WAIT
   WHERE SID = ?
";

      $cursor = $dbh->prepare($sql);
      $cursor->bind_param(1,$sid[$counter2]);
      $cursor->execute;
      $event = $cursor->fetchrow_array;
      $cursor->finish;

      if ($event eq "latch free") {
         logit("   Session $schema waiting on latch free, gathering additional info..");
         my ($p1,$p1raw,$p2,$p2raw,$p3,$p3raw,$latchname);

      # P1RAW is used to gather info from V$LATCH_CHILDREN
      # P2 holds the latch#, to join with V$LATCHNAME
         $sql = "
Select
   p1raw,
   p2
from v\$session_wait 
   where sid = ?
";

         $cursor = $dbh->prepare($sql);
         $cursor->bind_param(1,$sid[$counter2]);
         $cursor->execute;
         ($p1raw,$p2) = $cursor->fetchrow_array;
         $cursor->finish;

         $sql = "
Select 
   name
from v\$latchname where latch# = ?
";

         $cursor = $dbh->prepare($sql);
         $cursor->bind_param(1,$p2);
         $cursor->execute;
         ($latchname) = $cursor->fetchrow_array;
         $cursor->finish;

         text("This session is waiting on a \"$latchname\" latch.");
      } else {
         logit("   Session is not waiting on a latch free event. Good.");
      }
   }

   print << "EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Ora user</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>OS user</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>SID</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Serial#</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Status</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Process</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Program</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Command</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Rows</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Logon time</TH>
        <TR>
          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$username[$counter2]</TD>
          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$osuser[$counter2]</TD>
          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$sid[$counter2]</TD>
          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$serial[$counter2]</TD>
          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$status[$counter2]</TD>
          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$process[$counter2]</TD>
          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$program[$counter2]</TD>
          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$command[$counter2]</TD>
          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$rows_processed[$counter2]</TD>
          <TD BGCOLOR='$headingcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$logon_time[$counter2]</TD>
        </TR>
EOF
   if ($sqltext[$counter2]) {
      print <<"EOF";
        <TR>
          <TD BGCOLOR='$cellcolor' COLSPAN=10><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$sqltext[$counter2]<P>
            <TABLE>
              <TR>
EOF
   } else {
      print <<"EOF";
        <TR>
          <TD BGCOLOR='$cellcolor' COLSPAN=10><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>No SQL<P>
            <TABLE>
              <TR>
EOF
   }
   print <<"EOF";
                <TD>
                  <FORM METHOD=POST ACTION="$scriptname">
                    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
                    <INPUT TYPE=HIDDEN NAME="object_type" VALUE="SESSIONSTATS">
                    <INPUT TYPE=HIDDEN NAME="database" VALUE="$database">
                    <INPUT TYPE=HIDDEN NAME="schema" VALUE="$sid[$counter2]"> 
                    <INPUT TYPE=SUBMIT VALUE="Session stats">
                  </FORM>
                </TD>
EOF
   if ($sqltext[$counter2]) {
      print <<"EOF";
                <TD>
                  <FORM METHOD=POST ACTION="$scriptname">
                    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
                    <INPUT TYPE=HIDDEN NAME="object_type" VALUE="EXPLAIN">
                    <INPUT TYPE=HIDDEN NAME="database" VALUE="$database">
                    <INPUT TYPE=HIDDEN NAME="schema" VALUE="$sid[$counter2]">
                    <INPUT TYPE=HIDDEN NAME="explainschema" VALUE="$username[$counter2]">
                    <INPUT TYPE=HIDDEN NAME="arg" VALUE="$sqltext[$counter2]">
                    <INPUT TYPE=SUBMIT VALUE="Explain plan">
                  </FORM>
                </TD>
EOF
   }
   if ($oracle10) {
      if ((checkPriv("EXECUTE ANY PROCEDURE")) && ($status[$counter2] ne "KILLED")) {
         logit("SQL_TRACE is set to $sql_trace[$counter2]");
         if ($sql_trace[$counter2] eq "ENABLED") {
            logit("SQL_TRACE is ENABLED for this sesssion");
            $trace = "disable";
            $value = "Disable trace"; 
         }
         if ($sql_trace[$counter2] eq "DISABLED") {
            logit("SQL_TRACE is DISABLED for this sesssion");
            $trace = "enable";
            $value = "Enable trace"; 
         }
         print <<"EOF";
                <TD>
                  <FORM METHOD=POST ACTION="$scriptname">
                     <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
                     &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
                     &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
                     <INPUT TYPE=HIDDEN NAME="object_type" VALUE="TRACESESSION">
                     <INPUT TYPE=HIDDEN NAME="database" VALUE="$database">
                     <INPUT TYPE=HIDDEN NAME="sid" VALUE="$sid[$counter2]">
                     <INPUT TYPE=HIDDEN NAME="serial" VALUE="$serial[$counter2]">
                     <INPUT TYPE=HIDDEN NAME="trace" VALUE="$trace">
                     <INPUT TYPE=SUBMIT VALUE="$value">
                  </FORM>
                </TD>
EOF
      }
   }
   if (($altersystem) && ($status[$counter2] ne "KILLED")) {
      print <<"EOF";
                <TD>
                  <FORM METHOD=POST ACTION="$scriptname">
                     <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
                     <INPUT TYPE=HIDDEN NAME="object_type" VALUE="KILLSESSION">
                     <INPUT TYPE=HIDDEN NAME="database" VALUE="$database">
                     <INPUT TYPE=HIDDEN NAME="arg" VALUE="$sid[$counter2]">
                     <INPUT TYPE=HIDDEN NAME="schema" VALUE="$serial[$counter2]">
                     <INPUT TYPE=SUBMIT VALUE="Kill session">
                  </FORM>
                </TD>
EOF
   }
   print <<"EOF";
              </TR>
            </TABLE>
          </TD>
        </TR>
      </TABLE>
    </TD>
  </TR>
</TABLE>

<HR WIDTH="5%" ALIGN=LEFT>
EOF
   $counter2++;
   }

   print "<CENTER>\n";
   message("No sessions to display.") unless ($sessions);
   refreshButton("10");

   logit("Exit subroutine showSessions");

}

sub ObjectTable {

   logit("Enter subroutine ObjectTable");

# Usage: ObjectTable ($dbh,$sql,$text,$infotext);

# This sub is specifically for displaying a table with
# database object name, type, and owner.
# It will make each entry a hyperlink to obtain additional
# information about the object.

   my $sql	= shift;
   my $text	= shift;
   my $infotext	= shift;

   logit("   SQL = $sql");

   my ($cursor,@row,$object_name,$object_type,$schema,$count,$numfields,$field,$name);

   $infotext = "<FONT COLOR=\"$infocolor\">$infotext</FONT>";

   $cursor = $dbh->prepare($sql) or ErrorPage ("$DBI::errstr");
   $cursor->execute or ErrorPage ("$DBI::errstr");

   $count = 0;
   while (@row = $cursor->fetchrow_array) {
      $count++;
   }
   $cursor->finish or ErrorPage ("$DBI::errstr");
   if ($count != 0) {

      $cursor = $dbh->prepare($sql) or ErrorPage ("$DBI::errstr");
      $cursor->execute or ErrorPage ("$DBI::errstr");

      print "<P><B>$text</B></P>\n" if defined $text;
      print "<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>\n";
      print "  <TR>\n";
      print "    <TD WIDTH=100%>\n";
      print "      <TABLE BORDER=0 cellpadding=2 cellspacing=1>\n";
      $cursor = $dbh->prepare($sql) or ErrorPage ("$DBI::errstr");
      $cursor->execute or ErrorPage ("$DBI::errstr");
      $numfields = $cursor->{NUM_OF_FIELDS};

      for ($field=0; $field < $numfields; $field++) {
         $name = $cursor->{NAME}->[$field];
         print "      <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>$name</TH>";
      }
      while (@row = $cursor->fetchrow_array) {
         $object_name	=$row[0];
         $object_type	=$row[1];
         $schema	=$row[2];
         print "      <TR ALIGN=LEFT>";
         $_ = $row[0];
         s/ /+/;
         $object_name = $_;
         $_ = $row[1];
         s/ /+/;
         $object_type = $_;
         for ($field=0; $field < $numfields; $field++) {
            print "        <TD BGCOLOR='$cellcolor'";
            print " ALIGN=RIGHT" if ($row[$field] =~ /^\s*\.?\d/);
            if ($field == 0) {
               print "><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A href=$scriptname?database=$database&arg=$object_name&object_type=$object_type&schema=$schema>$row[$field]</A></TD>\n";
            } else {
               print "><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$row[$field]</TD>\n";
            }
         }
      print "        </TR>\n";
      }
      print "      </TABLE>\n";
      print "    </TD>\n";
      print "  </TR>\n";
      print "</TABLE>\n";
      $cursor->finish or ErrorPage ("$DBI::errstr");
   } else {
      print "<P><B>$infotext</B></P>\n" if ( defined $infotext );
   }

   logit("Exit subroutine ObjectTable");

   if ($DBI::errstr) {
      return($DBI::errstr);
   } else {
      return($count);
   }
}

sub framePage {

   logit("Enter subroutine framePage");

# Usage: framePage ($title,$heading,$font,$fontsize,$fontcolor,$bgcolor);

# Creates a HTML header with title

   my $title      = shift;
   my $heading    = shift;
   my $font       = shift;
   my $fontsize   = shift;
   my $fontcolor  = shift;
   my $bgcolor    = shift;

   my $schema	  = uc($username);

print << "EOF";
Content-type: Text/html\n\n
<HTML>
<HEAD>
  <TITLE>$database: Oracletool v$VERSION connected as $schema</TITLE>
</HEAD>
<FRAMESET COLS="150,*" BORDER="0">
<FRAME NAME="menu" SRC="$scriptname?database=$database&object_type=MENU">
<FRAME NAME="body" SRC="$scriptname?database=$database&schema=$schema&object_type=LISTUSERS">
</FRAMESET>
</HTML>
EOF

   logit("Exit subroutine framePage");

exit;
}

sub statsPackMenu {

   logit("Enter subroutine statsPackMenu");

   my ($sql,$cursor,$snap_count,$min_snap,$max_snap,$db_bounces);

   $statspack_schema = "PERFSTAT" unless $statspack_schema;

   $sql = "
SELECT * FROM 
   (SELECT TO_CHAR(COUNT(SNAP_ID ),'999,999,999,999')
FROM $statspack_schema.STATS\$SNAPSHOT),
   (SELECT TO_CHAR(MIN(SNAP_TIME),'Day, Month DD YYYY @ HH24:MI:SS')
FROM $statspack_schema.STATS\$SNAPSHOT),
   (SELECT TO_CHAR(MAX(SNAP_TIME),'Day, Month DD YYYY @ HH24:MI:SS')
FROM $statspack_schema.STATS\$SNAPSHOT),
   (SELECT TO_CHAR(COUNT(DISTINCT(STARTUP_TIME)),'999,999,999,999')
FROM $statspack_schema.STATS\$SNAPSHOT)
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   ($snap_count,$min_snap,$max_snap,$db_bounces) = $cursor->fetchrow_array;
   $cursor->finish;
   logit("   #Snap records = $snap_count");
   text("You have $snap_count snapshots available for analyzation spanning $db_bounces database startup(s).<BR>Oldest snapshot is $min_snap: Most recent is $max_snap.");

   text("Oracle Statspack functions.");

   Button("$scriptname?database=$database&object_type=STATSPACKADMIN&command=snapshot TARGET=body","Execute a snapshot","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=STATSPACKADMIN&command=statsgroups TARGET=body","Snapshot analyzation / admin","$headingcolor","CENTER","200");

   logit("Exit subroutine statsPackMenu");

}

sub rollbackMenu {

   logit("Enter subroutine rollbackMenu");

   my ($text,$link,$infotext,$sql);

   $sql = "
SELECT 
   S.SID					\"SID\",
   S.SERIAL#					\"Serial#\",
   NVL(s.username, 'None') 			\"Username\",
   S.PROGRAM					\"Program\",
   R.NAME					\"Segment name\",
   TO_CHAR(T.USED_UBLK*TO_NUMBER(X.VALUE),'999,999,999,999,999')	\"Size\"
FROM sys.v_\$rollname    r,
   sys.v_\$session     s,
   sys.v_\$transaction t,
   sys.v_\$parameter   x
WHERE s.taddr = t.addr
AND r.usn   = t.xidusn(+)
AND x.name  = 'db_block_size'
";

   $text = "Undo synopsis";
   $link = "";
   $infotext = "No undo segments are in use";
   DisplayTable($sql,$text,$link,$infotext);

   print "<p>\n";

   Button("$scriptname?database=$database&object_type=SHOWROLLBACKS TARGET=body","Rollback segment information","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=SHOWTRANSACTIONS TARGET=body","Transaction information","$headingcolor","CENTER","200");

   logit("Exit subroutine rollbackMenu");

}

sub backupMenu {

   logit("Enter subroutine backupMenu");

      Button("$scriptname?database=$database&object_type=RMANMONITOR TARGET=body","Monitor an active RMAN backup","$headingcolor","CENTER","200");

   if (backupsFound() && rmanCatalogExists()) {
      logit("   This database is backed up by RMAN and has a RMAN catalog.");
      Button("$scriptname?database=$database&object_type=RMANBACKUPS&command=menu TARGET=body","RMAN info via controlfiles","$headingcolor","CENTER","200");
      Button("$scriptname?database=$database&object_type=RMANCATALOGQUERY TARGET=body","RMAN info via catalog","$headingcolor","CENTER","200");
      return(0);
   } elsif (backupsFound()) {
      logit("   This database is backed up by RMAN, but has no RMAN catalog(s).");
      rmanBackups("menu");
   } elsif (rmanCatalogExists()) {
      logit("   This database is not backed up by RMAN, but has a RMAN catalog.");
      rmanCatalogQuery();
   } else {
      logit("   This database is not backed up by RMAN, nor does it have any RMAN catalogs.");
      message("This database is not backed up using RMAN.");
      message("This database contains no RMAN backup catalogs.");
   }

   logit("Exit subroutine backupMenu");

}

sub perfMenu {

   logit("Enter subroutine perfMenu");
   
   my ($user);

   print "</CENTER></FONT>\n";

   Button("$scriptname?database=$database&object_type=PERFORMANCE TARGET=body","Memory allocation & resources","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=SQLAREALIST TARGET=body","Shared SQL area","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=SESSIONWAIT TARGET=body","Session wait info","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=MTSINFO TARGET=body","Multi Threaded Server","$headingcolor","CENTER","200");

   if (checkPriv("ALTER SYSTEM")) {
      print <<"EOF";
<CENTER>
<P><HR WIDTH=90%><P>
<FORM METHOD="GET" ACTION="$scriptname">
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
  <INPUT TYPE="HIDDEN" NAME="arg" VALUE="ALTER SYSTEM FLUSH SHARED_POOL">
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="RUNSQL">
  <INPUT TYPE="SUBMIT" NAME="foo" VALUE="Flush the shared pool">
</FORM>
EOF
   }

   logit("Exit subroutine perfMenu");

}

sub tsDDL {

   logit("Enter subroutine tsDDL");

   logit("   Tablespace: $object_name");

   my ($sql,$cursor,$ddl,$size);

   $size	= $fontsize + 1;

   $dbh->{LongReadLen} = 10240;
   $dbh->{LongTruncOk} = 1;

   $sql = "SELECT DBMS_METADATA.GET_DDL('TABLESPACE','$object_name') FROM DUAL";
   logit("$sql");
   $cursor = $dbh->prepare($sql) || logit("$DBI::errstr");
   $cursor->execute || logit("$DBI::errstr");
   $ddl = $cursor->fetchrow_array || logit("$DBI::errstr");
   $cursor->finish;

   print "<input type=\"button\" name=\"foobar\" value=\"Close window\" onClick=\"window.close()\">";

   text("DDL for tablespace $object_name");

   print <<"EOF";
<BR>
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TR>
          <TD BGCOLOR='$cellcolor'>
            <FONT COLOR='$fontcolor' SIZE='$size' FACE='$font'>
            </CENTER>
            <PRE>
$ddl
            </PRE>
          </TD>
        </TR>
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF

   logit("Exit subroutine tsDDL");

}

sub objectDDL {

   logit("Enter subroutine objectDDL");
 
   my ($schema,$object_type,$object_name,$sql,$cursor,$ddl,$text,$link,$size);
   my ($indexes);

   $schema		= $query->param('schema'); 
   $object_type		= $query->param('objecttype'); 
   $object_name		= $query->param('object_name'); 
   $size		= $fontsize + 1;
                                                                                                                                         
   logit("   SCHEMA: $schema OBJECT TYPE: $object_type OBJECT_NAME: $object_name");

   # Indentation and line feeds
   logit("   Indentation and line feeds");
   $sql = "
BEGIN
   DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM,'PRETTY',TRUE);
END;
";
   $dbh->do($sql) || message("$DBI::errstr");

   # Terminate statements with a ";"
   logit("   Terminate statements with a ;");
   $sql = "
BEGIN
   DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM,'SQLTERMINATOR',TRUE);
END;
";
   $dbh->do($sql) || message("$DBI::errstr");

   # Show storage parameters
   logit("   Show storage parameters");
   $sql = "
BEGIN
   DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM,'STORAGE',TRUE);
END;
";
   $dbh->do($sql) || message("$DBI::errstr");

   # Show tablespace parameters
   logit("   Show tablespace parameters");
   $sql = "
BEGIN
   DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM,'TABLESPACE',TRUE);
END;
";
   $dbh->do($sql) || message("$DBI::errstr");

   # Show all non referential constraints
   logit("   Show all non referential constraints");
   $sql = "
BEGIN
   DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM,'CONSTRAINTS',TRUE);
END;
";
   $dbh->do($sql) || message("$DBI::errstr");

   # Show all referential constraints
   logit("   Show all referential constraints");
   $sql = "
BEGIN
   DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM,'REF_CONSTRAINTS',TRUE);
END;
";
   $dbh->do($sql) || message("$DBI::errstr");

   # Show constraint statements as alters, not part of the create table statement.
   # including create index commands, if neccessary. This will only display indexes
   # that are constraints though..
   logit("   Show constraint statements as alters");
   $sql = "
BEGIN
   DBMS_METADATA.SET_TRANSFORM_PARAM(DBMS_METADATA.SESSION_TRANSFORM,'CONSTRAINTS_AS_ALTER',TRUE);
END;
";
   $dbh->do($sql) || message("$DBI::errstr");

   $dbh->{LongReadLen} = 10240;
   $dbh->{LongTruncOk} = 1;

   $sql = "SELECT DBMS_METADATA.GET_DDL('$object_type','$object_name','$schema') FROM DUAL";
   logit("$sql");
   $cursor = $dbh->prepare($sql) || logit("$DBI::errstr");
   $cursor->execute || logit("$DBI::errstr");
   $ddl = $cursor->fetchrow_array || logit("$DBI::errstr");
   $cursor->finish;

   if ($oracle92 || $oracle10) {
      $sql = "SELECT DBMS_METADATA.GET_DEPENDENT_DDL('INDEX','$object_name','$schema') FROM DUAL";
      logit("$sql");
      $cursor = $dbh->prepare($sql) || logit("$DBI::errstr");
      $cursor->execute || logit("$DBI::errstr");
      $indexes = $cursor->fetchrow_array || logit("$DBI::errstr");
      $cursor->finish;
   } else {
      $indexes = "";
   }

   print "<input type=\"button\" name=\"foobar\" value=\"Close window\" onClick=\"window.close()\">";

   text("DDL for $schema.$object_name");

   print <<"EOF";
<BR>
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TR>
          <TD BGCOLOR='$cellcolor'>
            <FONT COLOR='$fontcolor' SIZE='$size' FACE='$font'>
            </CENTER>
            <PRE>
$ddl
$indexes
            </PRE>
          </TD>
        </TR>
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF

   logit("Exit subroutine objectDDL");
}

sub mtsInfo {

   logit("Enter subroution mtsInfo");

   my ($command,$sql,$text,$link,$infotext);

   $command = $query->param('command') || "";

   refreshButton();

# MTS Servers Life Cycle (Ernesto Hern\341ndez-Novich <emhn@telcel.net.ve>
# - Find out what is the maximum number of connections per dispatcher,
#   useful in estimating the number of dispatchers/servers.
# - Check if new servers are needed and created.
# - Check if unused servers are being terminated.
# - If both are 0 _permanently_, you have too many servers.
# - If both are >0 and _increase_, you have too few servers.
# - Use "HIGHWATER" as a reference to the maximum number of servers that
#   have been created since database start.

   $sql = "$copyright\n" .
      q{
SELECT
   MAXIMUM_CONNECTIONS		"Max connections",
   SERVERS_STARTED		"Started",
   SERVERS_TERMINATED		"Terminated",
   SERVERS_HIGHWATER		"Highwater"
FROM V$MTS
           };

   $text = "MTS shared servers life cycle";
   $link = "";
   DisplayTable($sql,$text,$link);

# MTS Servers Efficiency (Ernesto Hern\341ndez-Novich <emhn@telcel.net.ve>)
# - Check how busy shared servers are. They should always be 80% busy,
#   and balanced in average.
# - If latter servers are idle most of the time, remove some.
# - If servers approach 100% busy and balanced, add some.

   $sql = "$copyright\n" .
      q{
SELECT
   NAME						"Name",
   TO_CHAR(REQUESTS,'999,999,999')		"Requests",
   TO_CHAR((BUSY/(BUSY + IDLE)) * 100,'999.99')	"% busy"
FROM V$SHARED_SERVER
           };

   $text = "MTS shared servers efficiency";
   $link = "";
   DisplayTable($sql,$text,$link);


# MTS Dispatcher Usage (Ernesto Hern\341ndez-Novich <emhn@telcel.net.ve>)
# - Check how busy dispatchers are. They should always be less than 20%
#   busy, in a 'WAIT' status and more or less "balanced" in load.
# - If latter dispatchers are idle most of the time, remove some.
# - If dispatchers approach 100% busy and balanced, add some.
# - How many connections are being server by each dispatcher

   $sql = "$copyright\n" .
      q{
SELECT
   VD.NAME							"Name",
   VD.STATUS							"Status",
   TO_CHAR((VD.BUSY/(VD.BUSY + VD.IDLE)) * 100,'999.99')	"% busy",
   COUNT(VC.CIRCUIT)						"Connections"
FROM V$DISPATCHER VD,
     V$CIRCUIT VC
WHERE VD.PADDR = VC.DISPATCHER (+)
   GROUP BY VD.NAME, VD.STATUS, VD.BUSY, VD.IDLE
           };

   $text = "MTS dispatcher usage";
   $link = "";
   $infotext = "MTS does not appear to be active in this instance";
   DisplayTable($sql,$text,$link,$infotext);

   $sql = "$copyright\n" .
      q{
SELECT   
   S.USERNAME				"Oracle User",
   P.USERNAME				"OS User",
   S.SID				"Session",
   S.SERIAL#				"Serial",
   S.MACHINE				"Terminal",
   TO_CHAR(C.MESSAGES,'999,999')	"Messages",
   TO_CHAR(C.BYTES,'999,999,999,999')	"Bytes",
   C.BREAKS				"Breaks",
   S.PROGRAM				"Program"
FROM V$DISPATCHER D, V$CIRCUIT C, V$SESSION S, V$PROCESS P
   WHERE    D.PADDR = C.DISPATCHER
   AND      C.SADDR = S.SADDR
   AND      S.PADDR = P.ADDR
   };

   $text = "MTS dispatcher detail";
   $link = "";
   $infotext = "No dispatchers are busy at this time.";
   DisplayTable($sql,$text,$link,$infotext);

}

sub sessionMenu {

   logit("Enter subroutine sessionMenu");

   print "</CENTER></FONT>\n";

   # This is a specialized button to allow a choice of the type of 
   # sessions to display.

   print <<"EOF";
      <TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0 ALIGN=CENTER WIDTH=200>
        <TR>
          <TD VALIGN="TOP" WIDTH=100%>
            <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1 WIDTH=100%>
              <TR ALIGN="CENTER">
                <TD BGCOLOR='$cellcolor'><B><FONT SIZE="$menufontsize">
<A HREF=$scriptname?database=$database&object_type=SESSIONS&listing=all>Detail (All)&nbsp;</A>
<A HREF=$scriptname?database=$database&object_type=SESSIONS&listing=active>(Active)&nbsp;</A>
<A HREF=$scriptname?database=$database&object_type=SESSIONS&listing=inactive>(Not active)&nbsp;</A>
                </TD>
              </TR>
            </TABLE>
          </TD>
        </TR>
      </TABLE>
      <TABLE WIDTH="100" CELLPADDING="1" CELLSPACING="0" BORDER="0">
        <TD></TD>
      </TABLE>
EOF

#   Button("$scriptname?database=$database&object_type=SESSIONS TARGET=body","Detailed session listing (all)","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=SESSIONWAIT TARGET=body","Session wait info","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=SESSIONWAITBYEVENT TARGET=body","Top session wait by event","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=TOPSESSIONS TARGET=body","Session summary w/refresh","$headingcolor","CENTER","200");
   if ($oracle10 || $oracle11) {
      Button("$scriptname?database=$database&object_type=DATAPUMPJOBS TARGET=body","Datapump jobs","$headingcolor","CENTER","200");
   }
#   print "<P><HR WIDTH=90%><P>\n";
   print "<CENTER>\n";
   text("<B>Jump to detailed session info for a connected user..</B>");
print <<"EOF";
   <FORM METHOD=POST ACTION=$scriptname>
     <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
     <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
     <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="TOPSESSIONS">
<B>Choose a username</B> 
  <SELECT SIZE=1 NAME=username>
EOF
   $sql = "$copyright
SELECT
  DISTINCT USERNAME
FROM V\$SESSION
  WHERE USERNAME IS NOT NULL 
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   while ($user = $cursor->fetchrow) {
      print "    <OPTION>$user\n";
   }
   $cursor->finish;

   print <<"EOF";
        </SELECT>
        <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Display sessions">
      </FORM>
EOF

   $sql = "
SELECT 
   INITCAP(STATUS)			\"Status\",
   TO_CHAR(COUNT(STATUS),'999,999,999')	\"Count\"
FROM V\$SESSION WHERE USERNAME IS NOT NULL
   GROUP BY STATUS
";

   my $text = "# Active sessions, excluding background processes";
   my $link = "";
   my $infotext = "No active sessions this time.";
   DisplayTable($sql,$text,$link,$infotext);

   $sql = "
SELECT
   PROGRAM				\"Program\",
   OSUSER				\"OS user\",
   PROCESS				\"OS PID\",
   STATUS				\"Status\"
FROM V\$SESSION
   WHERE USERNAME IS NULL
ORDER BY PROGRAM
";

   $text = "Background process summary";
   $link = "";
   DisplayTable($sql,$text,$link);

   logit("Exit subroutine sessionMenu");

}

sub auditMenu {

   logit("Enter subroutine auditMenu");

   print "</CENTER></FONT>\n";

   Button("$scriptname?database=$database&object_type=AUDITADMIN&command=schemaobjects TARGET=body","Schema object auditing","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=ENTERAUDITS&command=statementobjects TARGET=body","SQL statement auditing","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=ENTERAUDITS&command=systemobjects TARGET=body","System privilege auditing","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=AUDITLIST TARGET=body","Remove audits","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=AUDITING TARGET=body","Display auditing records","$headingcolor","CENTER","200");

   logit("Exit subroutine auditMenu");

}

sub prefMenu {

   logit("Enter subroutine prefMenu");

   print "</FONT>\n";

   Button("$scriptname?database=$database&object_type=SHOWPROPS TARGET=body","Fonts etc.","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=SHOWTHEMES TARGET=body","Themes","$headingcolor","CENTER","200");

   logit("Exit subroutine prefMenu");

}

sub taskMenu {

   logit("Enter subroutine taskMenu");

   my $count;

   print "</FONT>\n";

   text("Database administration");

   if (checkPriv("CREATE USER")) {
      Button("$scriptname?database=$database&object_type=USERADMIN TARGET=body","User administration","$headingcolor","CENTER","200");
   } else {
      Button("","User administration","$headingcolor","CENTER","200");
      $count++;
   }
   
   if (checkPriv("ALTER SYSTEM")) {
      Button("$scriptname?database=$database&object_type=SESSIONLIST TARGET=body","Session administration","$headingcolor","CENTER","200");
   } else {
      Button("","Session administration","$headingcolor","CENTER","200");
      $count++;
   }

   if ( Auditing()) {
      if (checkPriv("AUDIT ANY")) {
         Button("$scriptname?database=$database&object_type=AUDITMENU TARGET=body","Auditing administration","$headingcolor","CENTER","200");
      } else {
         Button("","Auditing administration","$headingcolor","CENTER","200");
         $count++;
      }
   }

   if (checkPriv("ALTER ROLLBACK SEGMENT")) {
      Button("$scriptname?database=$database&object_type=RBSLIST TARGET=body","Rollback segment administration","$headingcolor","CENTER","200");
   } else {
      Button("","Rollback segment administration","$headingcolor","CENTER","200");
      $count++;
   }

   if (checkPriv("ALTER ANY PROCEDURE")) {
      Button("$scriptname?database=$database&object_type=OBJECTADMIN TARGET=body","Invalid object administration","$headingcolor","CENTER","200");
   } else {
      Button("","Object administration","$headingcolor","CENTER","200");
      $count++;
   }
#   if (checkPriv("CREATE TABLESPACE")) {
#      Button("$scriptname?database=$database&object_type=CREATETABLESPACE TARGET=body","Create tablespace","$headingcolor","CENTER","200");
#   }
   
   if (checkPriv("ALTER SYSTEM")) {
      Button("$scriptname?database=$database&object_type=PARAMETERADMIN TARGET=body","Parameter administration","$headingcolor","CENTER","200");
   } else {
      Button("","Parameter administration","$headingcolor","CENTER","200");
      $count++;
   }

   Button("$scriptname?database=$database&object_type=JOBSCHEDULER&command=connect TARGET=body","Job Scheduler (DBMS_JOB)","$headingcolor","CENTER","200");

   text("Database reports");
   Button("$scriptname?database=$database&object_type=USERSPACEREPORT TARGET=body","Space report by user","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=TSSPACEREPORT TARGET=body","Space report by tablespace / user","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=FILEFRAGREPORT TARGET=body","Datafile fragmentation report","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=ENTEREXTENTREPORT TARGET=body","Object extent report","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=HEALTHCHECKMENU TARGET=body","Multi instance reports","$headingcolor","CENTER","200");

   $username = uc($username);

   message("<CENTER>You ($username) do not have authority to enter one or more of the DBA areas.") if $count;

   logit("Exit subroutine taskMenu");

}

sub objectAdmin {

   logit("Enter subroutine objectAdmin");

   invalidObjectList();

   logit("Exit subroutine objectAdmin");

}

sub auditAdmin {

   my $command = $query->param('command');

   logit("Enter subroutine auditAdmin");

   my ($sql,$text,$link,$infotext,$cols,$checkbox,$target,$submittext);

   $sql         = "SELECT USERNAME FROM DBA_USERS ORDER BY USERNAME";
   $text        = "Schema object auditing: Select one or more users to set auditing options.";
   $link        = "";
   $infotext    = "";
   $cols        = $schema_cols;
   $checkbox    = "Yep";
   $target      = "ENTERAUDITS";
   $submittext  = "Choose audit options";
   $command     = "$command";

   DisplayColTable($sql,$text,$link,$infotext,$cols,$checkbox,$target,$submittext,$command);

   logit("Exit subroutine auditAdmin");

}

sub enterAudits {

   logit("Enter subroutine enterAudits");

   my ($sql,$cursor,$privilege,@statement_options,@system_privs);
   my ($foo,@users,@sqlusers,$username,@params,$param,$count);
   my ($tables,$views,$sequences,$procedures,$functions,$packages);
   my ($libraries,$directories,$owner,$object_name,$command);
   my ($statement_option);

   $command = $query->param('command');

   # Get a list of the usernames passed

   @params = $query->param;

   if ($command eq "systemobjects") {

      message("System privilege auditing.<BR>Multiple statements and users may be selected by holding down the &lt;CTRL&gt; key. The statement options you choose will be set for all users that you have highlighted.");

         print <<"EOF";
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
  <INPUT TYPE="HIDDEN" NAME="arg" VALUE="dostatementaudits">
  <B>AUDIT&nbsp;
  <SELECT SIZE=5 NAME=privilege MULTIPLE>
EOF
      $sql = "$copyright
SELECT 
   DISTINCT PRIVILEGE
FROM DBA_SYS_PRIVS
   WHERE PRIVILEGE NOT LIKE '% ANY %'
ORDER BY PRIVILEGE
";
      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      while ($privilege = $cursor->fetchrow_array) {
         print "<OPTION>$privilege\n";
      }
      $cursor->finish;
      print "</SELECT>\nBY&nbsp;<SELECT SIZE=5 NAME=users MULTIPLE>";
      $sql = "$copyright
SELECT 
   USERNAME
FROM DBA_USERS
   ORDER BY USERNAME
";
      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      while ($username = $cursor->fetchrow_array) {
         print "<OPTION>$username\n";
      }
      $cursor->finish;
      print <<"EOF";
  </SELECT>
  <BR>
  BY&nbsp;
  <INPUT TYPE="RADIO" NAME="by" VALUE="SESSION" CHECKED>session
  <INPUT TYPE="RADIO" NAME="by" VALUE="ACCESS">access
  <BR>
  WHENEVER&nbsp;
  <INPUT TYPE="CHECKBOX" NAME="whenever~SUCCESSFUL" CHECKED>successful
  <INPUT TYPE="CHECKBOX" NAME="whenever~NOTSUCCESSFUL" CHECKED>not successful
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Submit change">
</FORM>
EOF

   }

   if ($command eq "statementobjects") {

         @statement_options = (
"CLUSTER",
"DATABASE LINK",
"DIRECTORY",
"INDEX",
"NOT EXISTS",
"PROCEDURE",
"PROFILE",
"PUBLIC DATABASE LINK",
"PUBLIC SYNONYM",
"ROLE",
"ROLLBACK SEGMENT",
"SEQUENCE",
"SESSION",
"SYNONYM",
"SYSTEM AUDIT",
"SYSTEM GRANT",
"TABLE",
"TABLESPACE",
"TRIGGER",
"USER",
"VIEW",
"ALTER SEQUENCE",
"ALTER TABLE",
"COMMENT TABLE",
"DELETE TABLE",
"EXECUTE PROCEDURE",
"GRANT DIRECTORY",
"GRANT PROCEDURE",
"GRANT SEQUENCE",
"GRANT TABLE",
"INSERT TABLE",
"LOCK TABLE",
"SELECT SEQUENCE",
"SELECT TABLE",
"UPDATE TABLE"
   );

      message("SQL statement auditing.<BR>Multiple statements and users may be selected by holding down the &lt;CTRL&gt; key. The statement options you choose will be set for all users that you have highlighted.");

         print <<"EOF";
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
  <INPUT TYPE="HIDDEN" NAME="arg" VALUE="dostatementaudits">
  <B>AUDIT&nbsp;
  <SELECT SIZE=5 NAME=privilege MULTIPLE>
EOF
      foreach $statement_option (@statement_options) {
         print "<OPTION>$statement_option\n";
      }
      print "</SELECT>\nBY&nbsp;<SELECT SIZE=5 NAME=users MULTIPLE>";
      $sql = "$copyright
SELECT 
   USERNAME FROM DBA_USERS
ORDER BY USERNAME
";
      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      while ($username = $cursor->fetchrow_array) {
         print "<OPTION>$username\n";
      }
      $cursor->finish;
      print <<"EOF";
  </SELECT>
  <BR>
  BY&nbsp;
  <INPUT TYPE="RADIO" NAME="by" VALUE="SESSION" CHECKED>session
  <INPUT TYPE="RADIO" NAME="by" VALUE="ACCESS">access
  <BR>
  WHENEVER&nbsp;
  <INPUT TYPE="CHECKBOX" NAME="whenever~SUCCESSFUL" CHECKED>successful
  <INPUT TYPE="CHECKBOX" NAME="whenever~NOTSUCCESSFUL" CHECKED>not successful
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Submit change">
</FORM>
EOF

   }

   if ($command eq "schemaobjects") {

      foreach $param(@params) {
         if ($param =~ /checked~/) {
            $count++;
            ($foo,$username) = split("~", $param);
            push @users, $username;
            push @sqlusers, "'$username'";
            logit("   Username = $username");
         }
      }
      logit("   Number of users passed: $count");

      unless ($count) {
         message("You must select at least one user!");
         footer();
      }

      # Join the usernames to be suitable for a "IN"
      # clause.

      @sqlusers = join(",", @sqlusers);

      logit("   Users     = @users");
      logit("   SQL Users = @sqlusers");

      message("Schema object auditing.<BR>Multiple object names may be selected by holding down the &lt;CTRL&gt; key. The auditing options you choose will be set for all objects that you have highlighted.");

      # Find out how many of each auditable object
      # We have to work with. Snapshots are not
      # included here, as they don't seem to have
      # an object type# associated with them. 

         $sql = "$copyright
SELECT
   COUNT(DECODE(TYPE, 2, OBJ#, '')) \"Table\",
   COUNT(DECODE(TYPE, 4, OBJ#, '')) \"View`\",
   COUNT(DECODE(TYPE, 6, OBJ#, '')) \"Sequence\",
   COUNT(DECODE(TYPE, 7, OBJ#, '')) \"Procedure\",
   COUNT(DECODE(TYPE, 8, OBJ#, '')) \"Function\",
   COUNT(DECODE(TYPE, 9, OBJ#, '')) \"Package\",
   COUNT(DECODE(TYPE, 22, OBJ#, '')) \"Library\",
   COUNT(DECODE(TYPE, 23, OBJ#, '')) \"Directory\"
FROM SYS.OBJ\$
   WHERE OWNER# IN
(
SELECT USER_ID
   FROM DBA_USERS
WHERE USERNAME IN (@sqlusers)
)
" if $oracle7;

         $sql = "$copyright
SELECT
   COUNT(DECODE(TYPE#, 2, OBJ#, '')) \"Table\",
   COUNT(DECODE(TYPE#, 4, OBJ#, '')) \"View`\",
   COUNT(DECODE(TYPE#, 6, OBJ#, '')) \"Sequence\",
   COUNT(DECODE(TYPE#, 7, OBJ#, '')) \"Procedure\",
   COUNT(DECODE(TYPE#, 8, OBJ#, '')) \"Function\",
   COUNT(DECODE(TYPE#, 9, OBJ#, '')) \"Package\",
   COUNT(DECODE(TYPE#, 22, OBJ#, '')) \"Library\",
   COUNT(DECODE(TYPE#, 23, OBJ#, '')) \"Directory\"
FROM SYS.OBJ\$
   WHERE OWNER# IN
(
SELECT USER_ID
   FROM DBA_USERS
WHERE USERNAME IN (@sqlusers)
)
" if $notoracle7;

      $cursor=$dbh->prepare($sql);
      $cursor->execute;
      ($tables,$views,$sequences,$procedures,$functions,$packages,$libraries,$directories) = $cursor->fetchrow_array;
      $cursor->finish;

      logit("   Tables - $tables: Views - $views: Sequences - $sequences: Procedures - $procedures: Functions - $functions: Packages - $packages: Libraries - $libraries: Directories - $directories");

      # Start cycling through the object types, displaying them
      # if any exist for any of the selected schemas.

      if ($tables) {

         text("Audit table objects.");

         $sql = "$copyright
SELECT 
   OWNER,
   TABLE_NAME
FROM DBA_TABLES
   WHERE OWNER IN (@sqlusers)
ORDER BY OWNER, TABLE_NAME
";
         print <<"EOF";
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
  <INPUT TYPE="HIDDEN" NAME="arg" VALUE="doschemaaudits">
  <B>AUDIT&nbsp;
  <INPUT TYPE="CHECKBOX" NAME="audit~ALL">All&nbsp;&nbsp;--
  <INPUT TYPE="CHECKBOX" NAME="audit~ALTER">Alter,
  <INPUT TYPE="CHECKBOX" NAME="audit~AUDIT">Audit,
  <INPUT TYPE="CHECKBOX" NAME="audit~COMMENT">Comment,
  <INPUT TYPE="CHECKBOX" NAME="audit~DELETE">Delete,
  <INPUT TYPE="CHECKBOX" NAME="audit~GRANT">Grant,
  <INPUT TYPE="CHECKBOX" NAME="audit~INDEX">Index,
  <INPUT TYPE="CHECKBOX" NAME="audit~INSERT">Insert,
  <INPUT TYPE="CHECKBOX" NAME="audit~LOCK">Lock,
  <INPUT TYPE="CHECKBOX" NAME="audit~RENAME">Rename,
  <INPUT TYPE="CHECKBOX" NAME="audit~SELECT">Select,
  <INPUT TYPE="CHECKBOX" NAME="audit~UPDATE">Update
  <BR>
  ON&nbsp
  <SELECT SIZE=5 NAME=object MULTIPLE>
EOF

         $cursor = $dbh->prepare($sql);
         $cursor->execute;
         while (($owner,$object_name) = $cursor->fetchrow_array) {
            print "<OPTION>$owner.$object_name\n";
         }
         print <<"EOF";
  </SELECT>
  <BR>
  BY&nbsp;
  <INPUT TYPE="RADIO" NAME="by" VALUE="SESSION" CHECKED>session
  <INPUT TYPE="RADIO" NAME="by" VALUE="ACCESS">access
  <BR>
  WHENEVER&nbsp;
  <INPUT TYPE="CHECKBOX" NAME="whenever~SUCCESSFUL" CHECKED>successful
  <INPUT TYPE="CHECKBOX" NAME="whenever~NOTSUCCESSFUL" CHECKED>not successful
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Submit change">
</FORM>
<CENTER>
<P><HR WIDTH=90%><P>
EOF
      }

      if ($views) {

         text("Audit view objects.");

         $sql = "$copyright
SELECT
   OWNER,
   VIEW_NAME
FROM DBA_VIEWS
   WHERE OWNER IN (@sqlusers)
ORDER BY OWNER, VIEW_NAME
";
         print <<"EOF";
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
  <INPUT TYPE="HIDDEN" NAME="arg" VALUE="doschemaaudits">
  <B>AUDIT&nbsp;
  <INPUT TYPE="CHECKBOX" NAME="audit~ALL">All&nbsp;&nbsp;--
  <INPUT TYPE="CHECKBOX" NAME="audit~AUDIT">Audit,
  <INPUT TYPE="CHECKBOX" NAME="audit~COMMENT">Comment,
  <INPUT TYPE="CHECKBOX" NAME="audit~DELETE">Delete,
  <INPUT TYPE="CHECKBOX" NAME="audit~GRANT">Grant,
  <INPUT TYPE="CHECKBOX" NAME="audit~INSERT">Insert,
  <INPUT TYPE="CHECKBOX" NAME="audit~LOCK">Lock,
  <INPUT TYPE="CHECKBOX" NAME="audit~RENAME">Rename,
  <INPUT TYPE="CHECKBOX" NAME="audit~SELECT">Select,
  <INPUT TYPE="CHECKBOX" NAME="audit~UPDATE">Update
  <BR>
  ON&nbsp
  <SELECT SIZE=5 NAME=object MULTIPLE>
EOF

         $cursor = $dbh->prepare($sql);
         $cursor->execute;
         while (($owner,$object_name) = $cursor->fetchrow_array) {
            print "<OPTION>$owner.$object_name\n";
         }
         print <<"EOF";
  </SELECT>
  <BR>
  BY&nbsp;
  <INPUT TYPE="RADIO" NAME="by" VALUE="SESSION" CHECKED>session
  <INPUT TYPE="RADIO" NAME="by" VALUE="ACCESS">access
  <BR>
  WHENEVER&nbsp;
  <INPUT TYPE="CHECKBOX" NAME="whenever~SUCCESSFUL" CHECKED>successful
  <INPUT TYPE="CHECKBOX" NAME="whenever~NOTSUCCESSFUL" CHECKED>not successful
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Submit change">
</FORM>
<CENTER>
<P><HR WIDTH=90%><P>
EOF
      }

      if ($sequences) {

         text("Audit sequence objects.");

         $sql = "$copyright
SELECT
   SEQUENCE_OWNER,
   SEQUENCE_NAME
FROM DBA_SEQUENCES
   WHERE SEQUENCE_OWNER IN (@sqlusers)
ORDER BY SEQUENCE_OWNER, SEQUENCE_NAME
";
         print <<"EOF";
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
  <INPUT TYPE="HIDDEN" NAME="arg" VALUE="doschemaaudits">
  <B>AUDIT&nbsp;
  <INPUT TYPE="CHECKBOX" NAME="audit~ALL">All&nbsp;&nbsp;--
  <INPUT TYPE="CHECKBOX" NAME="audit~ALTER">Alter,
  <INPUT TYPE="CHECKBOX" NAME="audit~AUDIT">Audit,
  <INPUT TYPE="CHECKBOX" NAME="audit~GRANT">Grant,
  <INPUT TYPE="CHECKBOX" NAME="audit~RENAME">Rename
  <BR>
  ON&nbsp
  <SELECT SIZE=5 NAME=object MULTIPLE>
EOF

         $cursor = $dbh->prepare($sql);
         $cursor->execute;
         while (($owner,$object_name) = $cursor->fetchrow_array) {
            print "<OPTION>$owner.$object_name\n";
         }
         print <<"EOF";
  </SELECT>
  <BR>
  BY&nbsp;
  <INPUT TYPE="RADIO" NAME="by" VALUE="SESSION" CHECKED>session
  <INPUT TYPE="RADIO" NAME="by" VALUE="ACCESS">access
  <BR>
  WHENEVER&nbsp;
  <INPUT TYPE="CHECKBOX" NAME="whenever~SUCCESSFUL" CHECKED>successful
  <INPUT TYPE="CHECKBOX" NAME="whenever~NOTSUCCESSFUL" CHECKED>not successful
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Submit change">
</FORM>
<CENTER>
<P><HR WIDTH=90%><P>
EOF
      }

      if ($procedures || $packages || $functions) {

         text("Audit source objects.");

         $sql = "$copyright
SELECT
   OWNER,
   OBJECT_NAME
FROM DBA_OBJECTS
   WHERE OWNER IN (@sqlusers)
   AND OBJECT_TYPE IN ('PACKAGE','PROCEDURE','FUNCTION')
ORDER BY OWNER, OBJECT_NAME
";
         print <<"EOF";
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
  <INPUT TYPE="HIDDEN" NAME="arg" VALUE="doschemaaudits">
  <B>AUDIT&nbsp;
  <INPUT TYPE="CHECKBOX" NAME="audit~ALL">All&nbsp;&nbsp;--
  <INPUT TYPE="CHECKBOX" NAME="audit~AUDIT">Audit,
  <INPUT TYPE="CHECKBOX" NAME="audit~EXECUTE">Execute,
  <INPUT TYPE="CHECKBOX" NAME="audit~GRANT">Grant,
  <INPUT TYPE="CHECKBOX" NAME="audit~RENAME">Rename
  <BR>
  ON&nbsp
  <SELECT SIZE=5 NAME=object MULTIPLE>
EOF

         $cursor = $dbh->prepare($sql);
         $cursor->execute;
         while (($owner,$object_name) = $cursor->fetchrow_array) {
            print "<OPTION>$owner.$object_name\n";
         }
         print <<"EOF";
  </SELECT>
  <BR>
  BY&nbsp;
  <INPUT TYPE="RADIO" NAME="by" VALUE="SESSION" CHECKED>session
  <INPUT TYPE="RADIO" NAME="by" VALUE="ACCESS">access
  <BR>
  WHENEVER&nbsp;
  <INPUT TYPE="CHECKBOX" NAME="whenever~SUCCESSFUL" CHECKED>successful
  <INPUT TYPE="CHECKBOX" NAME="whenever~NOTSUCCESSFUL" CHECKED>not successful
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Submit change">
</FORM>
<CENTER>
<P><HR WIDTH=90%><P>
EOF
      }

      if ($libraries) {

         text("Audit library objects.");

         $sql = "$copyright
SELECT 
   OWNER,
   LIBRARY_NAME
FROM DBA_LIBRARIES
   WHERE OWNER IN (@sqlusers)
ORDER BY OWNER, LIBRARY_NAME
";
      print <<"EOF";
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
  <INPUT TYPE="HIDDEN" NAME="arg" VALUE="doschemaaudits">
  <B>AUDIT&nbsp;
  <INPUT TYPE="CHECKBOX" NAME="audit~ALL">All&nbsp;&nbsp;--
  <INPUT TYPE="CHECKBOX" NAME="audit~EXECUTE">Execute,
  <INPUT TYPE="CHECKBOX" NAME="audit~GRANT">Grant
  <BR>
  ON&nbsp
  <SELECT SIZE=5 NAME=object MULTIPLE>
EOF

         $cursor = $dbh->prepare($sql);
         $cursor->execute;
         while (($owner,$object_name) = $cursor->fetchrow_array) {
            print "<OPTION>$owner.$object_name\n";
         }
         print <<"EOF";
  </SELECT>
  <BR>
  BY&nbsp;
  <INPUT TYPE="RADIO" NAME="by" VALUE="SESSION" CHECKED>session
  <INPUT TYPE="RADIO" NAME="by" VALUE="ACCESS">access
  <BR>
  WHENEVER&nbsp;
  <INPUT TYPE="CHECKBOX" NAME="whenever~SUCCESSFUL" CHECKED>successful
  <INPUT TYPE="CHECKBOX" NAME="whenever~NOTSUCCESSFUL" CHECKED>not successful
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Submit change">
</FORM>
<CENTER>
<P><HR WIDTH=90%><P>
EOF
      }

      if ($directories) {

         text("Audit directory objects.");

         $sql = "$copyright
SELECT 
   OWNER,
   DIRECTORY_NAME
FROM DBA_DIRECTORIES
   WHERE OWNER IN (@sqlusers)
ORDER BY OWNER, DIRECTORY_NAME
";
         print <<"EOF";
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
  <INPUT TYPE="HIDDEN" NAME="arg" VALUE="doschemaaudits">
  <B>AUDIT&nbsp;
  <INPUT TYPE="CHECKBOX" NAME="audit~ALL">All&nbsp;&nbsp;--
  <INPUT TYPE="CHECKBOX" NAME="audit~AUDIT">Audit,
  <INPUT TYPE="CHECKBOX" NAME="audit~GRANT">Grant,
  <INPUT TYPE="CHECKBOX" NAME="audit~READ">Read
  <BR>
  ON&nbsp
  <SELECT SIZE=5 NAME=object MULTIPLE>
EOF

         $cursor = $dbh->prepare($sql);
         $cursor->execute;
         while (($owner,$object_name) = $cursor->fetchrow_array) {
            print "<OPTION>$owner.$object_name\n";
         }
         print <<"EOF";
  </SELECT>
  <BR>
  BY&nbsp;
  <INPUT TYPE="RADIO" NAME="by" VALUE="SESSION" CHECKED>session
  <INPUT TYPE="RADIO" NAME="by" VALUE="ACCESS">access
  <BR>
  WHENEVER&nbsp;
  <INPUT TYPE="CHECKBOX" NAME="whenever~SUCCESSFUL" CHECKED>successful
  <INPUT TYPE="CHECKBOX" NAME="whenever~NOTSUCCESSFUL" CHECKED>not successful
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Submit change">
</FORM>
<CENTER>
<P><HR WIDTH=90%><P>
EOF
      }
   }

   logit("Exit subroutine enterAudits");

}

sub invalidObjectList {

   logit("Enter subroutine invalidObjectList");

   my ($username,$sql,$cursor,$owner,$object_type,$object_name,$object_id);
   my ($count);

   $username = shift;

   $sql = "$copyright
SELECT COUNT(*)
   FROM DBA_OBJECTS
WHERE STATUS IN ('INVALID','UNUSABLE')
";

   $sql = "$copyright
SELECT COUNT(*)
   FROM DBA_OBJECTS
WHERE OWNER = '$username'
AND STATUS IN ('INVALID','UNUSABLE')
" if ($username);

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $count = $cursor->fetchrow_array;
   $cursor->finish;

   unless ($count) {
      message("There are no invalid objects to compile");
      footer();
   }

   text("Select the objects you would like to compile.\n");

# ORDER_OBJECT_BY_DEPENDENCY is gone in 8.1.7. Why?

   $sql = "$copyright
SELECT
   OWNER,
   OBJECT_TYPE,
   OBJECT_NAME,
   A.OBJECT_ID
FROM
   DBA_OBJECTS A,
   SYS.ORDER_OBJECT_BY_DEPENDENCY B
WHERE
   A.OBJECT_ID = B.OBJECT_ID(+) AND
";
   $sql .= "   OWNER = '$username' AND\n" if $username;
   $sql .= "
    STATUS IN ('INVALID','UNUSABLE')
    ORDER BY
    DLEVEL DESC,
    OBJECT_TYPE,
    OBJECT_NAME
";

   if ($oraclei) {

      $sql = "$copyright
SELECT
   OWNER,
   OBJECT_TYPE,
   OBJECT_NAME,
   OBJECT_ID
FROM
   DBA_OBJECTS
WHERE
";
      $sql .= "   OWNER = '$username' AND\n" if $username;
      $sql .= "
    STATUS IN ('INVALID','UNUSABLE')
    ORDER BY
    OBJECT_TYPE,
    OBJECT_NAME
";

   }

   logit("   invalidObjectList SQL:\n$sql");

   # Print the heading

   print <<"EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <FORM METHOD=POST ACTION=$scriptname>
    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
    <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Compile marked objects">
    <P>
    <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
    <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
    <INPUT TYPE="HIDDEN" NAME="arg" VALUE="compile">
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Mark</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Owner</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Object type</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Name</TH>
EOF

   $cursor = $dbh->prepare($sql);
   $cursor->execute;

   while (($owner,$object_type,$object_name,$object_id) = $cursor->fetchrow) {
      print <<"EOF";
        <TR>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><INPUT TYPE=CHECKBOX NAME=compile_$object_id></TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$owner</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$object_type</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$object_name</TD>
        </TR>
EOF
      }
   $cursor->finish;
   print <<"EOF";
      </TABLE>
    </TD>
  </TR>
  </FORM>
</TABLE>
EOF

   logit("Exit subroutine invalidObjectList");

}

sub rbsList {

   logit("Enter subroutine rbsList");

   my ($sql,$cursor,$sql1,$cursor1,$id);
   my ($rbs,$owner,$tsname,$bytes,$init,$next,$extents,$max,$optimal,$status,$writes,$waits,$xacts);

   text("Rollbacks will shrink to OPTIMAL unless other value is specified.");

   $sql = "$copyright
SELECT
   A.SEGMENT_NAME,
   B.SEGMENT_ID,
   A.OWNER,
   A.TABLESPACE_NAME,
   B.STATUS,
   TO_CHAR(A.BYTES,'999,999,999,999'),
   TO_CHAR(A.INITIAL_EXTENT,'999,999,999,999'),
   TO_CHAR(A.NEXT_EXTENT,'999,999,999,999'),
   TO_CHAR(A.EXTENTS,'999,999,999,999'),
   TO_CHAR(A.MAX_EXTENTS,'999,999,999,999')
FROM DBA_SEGMENTS A, DBA_ROLLBACK_SEGS B
   WHERE A.SEGMENT_TYPE = 'ROLLBACK'
   AND A.SEGMENT_NAME = B.SEGMENT_NAME
   AND ( B.INSTANCE_NUM =
      ( SELECT VALUE FROM V\$PARAMETER
           WHERE NAME = 'instance_number' )
         OR B.INSTANCE_NUM IS NULL )
ORDER BY A.SEGMENT_NAME, A.TABLESPACE_NAME
";

   print <<"EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <FORM METHOD=POST ACTION=$scriptname>
    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
    <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Alter rollback(s)"> <B>&nbsp;Shrink to&nbsp;</B>
    <INPUT TYPE=TEXT NAME=shrinkto SIZE=10> 
    <P>
    <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
    <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
    <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
    <INPUT TYPE="HIDDEN" NAME="arg" VALUE="alter_rollbacks">
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Online</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Shrink</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Offline</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>RBS</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Owner</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Tablespace</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Status</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Bytes</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Optimal</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Initial extent</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Next extent</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Extents</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Max extents</TH>
EOF

   $cursor = $dbh->prepare($sql);
   $cursor->execute;

   while (($rbs,$id,$owner,$tsname,$status,$bytes,$init,$next,$extents,$max) = $cursor->fetchrow_array) {
      $sql1 = "
SELECT
   NVL(TO_CHAR(OPTSIZE,'999,999,999,999'),'Not set')
FROM V\$rollstat
   WHERE USN = $id
";
      $cursor1 = $dbh->prepare($sql1);
      $cursor1->execute;
      $optimal = $cursor1->fetchrow_array;
      $optimal = "Unknown" unless $optimal;
      $cursor1->finish;
      print <<"EOF";
        <TR>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><INPUT TYPE=CHECKBOX NAME=alter~$rbs~online></TD>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><INPUT TYPE=CHECKBOX NAME=alter~$rbs~shrink></TD>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><INPUT TYPE=CHECKBOX NAME=alter~$rbs~offline></TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$rbs</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$owner</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$tsname</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$status</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$bytes</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$optimal</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$init</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$next</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$extents</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$max</TD>
        </TR>
EOF
   }
   $cursor->finish;
   print <<"EOF";
      </TABLE>
    </TD>
  </TR>
  </FORM>
</TABLE>
EOF

   logit("Exit subroutine rbsList");

}


sub sessionList {

   logit("Enter subroutine sessionList");

   my ($sql,$cursor,$status);
   my ($username,$sid,$serial,$osuser,$command,$logon_time,$process,$machine);

   refreshButton();

   text("Select the sessions you would like to kill.\n");

   $sql = "$copyright
SELECT 
   USERNAME,
   SID,
   SERIAL#,
   STATUS,
   OSUSER,
   DECODE(COMMAND,
        '0','No command in progress',
        '1','Create table',
        '2','Insert',
        '3','Select',
        '4','Create cluster',
        '5','Alter cluster',
        '6','Update',
        '7','Delete',
        '8','Drop cluster',
        '9','Create index',
        '10','Drop index',
        '11','Alter index',
        '12','Drop table',
        '13','Create sequence',
        '14','Alter sequence',
        '15','Alter table',
        '16','Drop sequence',
        '17','Grant',
        '18','Revoke',
        '19','Create synonym',
        '20','Drop synonym',
        '21','Create view',
        '22','Drop view',
        '23','Validate index',
        '24','Create procedure',
        '25','Alter procedure',
        '26','Lock table',
        '27','No operation in progress',
        '28','Rename',
        '29','Comment',
        '30','Audit',
        '31','Noaudit',
        '32','Create database link',
        '33','Drop database link',
        '34','Create database',
        '35','Alter database',
        '36','Create rollback segment',
        '37','Alter rollback segment',
        '38','Drop rollback segment',
        '39','Create tablespace',
        '40','Alter tablespace',
        '41','Drop tablespace',
        '42','Alter session',
        '43','Alter user',
        '44','Commit',
        '45','Rollback',
        '46','Savepoint',
        '47','PL/SQL Execute',
        '48','Set transaction',
        '49','Alter system switch log',
        '50','Explain',
        '51','Create user',
        '52','Create role',
        '53','Drop user',
        '54','Drop role',
        '55','Set role',
        '56','Create schema',
        '57','Create control file',
        '58','Alter tracing',
        '59','Create trigger',
        '60','Alter trigger',
        '61','Drop trigger',
        '62','Analyze table',
        '63','Analyze index',
        '64','Analyze cluster',
        '65','Create profile',
        '66','Drop profile',
        '67','Alter profile',
        '68','Drop procedure',
        '69','Drop procedure',
        '70','Alter resource cost',
        '71','Create snapshot log',
        '72','Alter snapshot log',
        '73','Drop snapshot log',
        '74','Create snapshot',
        '75','Alter snapshot',
        '76','Drop snapshot',
        '79','Alter role',
        '85','Truncate table',
        '86','Truncate cluster',
        '88','Alter view',
        '91','Create function',
        '92','Alter function',
        '93','Drop function',
        '94','Create package',
        '95','Alter package',
        '96','Drop package',
        '97','Create package body',
        '98','Alter package body',
        '99','Drop package body'),
   TO_CHAR(LOGON_TIME,'Day MM/DD/YY HH24:MI'),
   PROCESS,
   MACHINE
FROM V\$SESSION
   WHERE USERNAME IS NOT NULL
   ORDER BY USERNAME, STATUS, SID, SERIAL#
";

   # Print the heading

   print <<"EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <FORM METHOD=POST ACTION=$scriptname>
    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
    <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Kill marked sessions"><BR>
    <P>
    <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
    <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
    <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
    <INPUT TYPE="HIDDEN" NAME="arg" VALUE="killsessions">
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Mark</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Ora user</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>SID</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Serial#</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Status</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>OS user</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Command</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Logon time</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Process</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Machine</TH>
EOF

   $cursor = $dbh->prepare($sql);
   $cursor->execute;

   while (($username,$sid,$serial,$status,$osuser,$command,$logon_time,$process,$machine) = $cursor->fetchrow_array) {
      print <<"EOF";
        <TR>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><INPUT TYPE=CHECKBOX NAME=killsession_$sid~$serial></TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$username</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$sid</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$serial</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$status</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$osuser</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$command</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$logon_time</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$process</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$machine</TD>
        </TR>
EOF
   }
   $cursor->finish;
   print <<"EOF";
      </TABLE>
    </TD>
  </TR>
  </FORM>
</TABLE>
EOF

   refreshButton();

   logit("Exit subroutine sessionList");

}

sub auditList {

   logit("Enter subroutine auditList");

   my ($sql,$cursor,$username,$audit_option,$new_audit_option,$count);
   my ($object_name,$object_type,$owner);

   $sql = "$copyright
SELECT COUNT(*) FROM DBA_STMT_AUDIT_OPTS
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;

   $count = $cursor->fetchrow_array;

   $cursor->finish;

   if ($count) {

      text("SQL statement / System audits");

      $sql = "$copyright
SELECT
   AUDIT_OPTION         \"Audit option\",
   USER_NAME            \"Username\"
FROM DBA_STMT_AUDIT_OPTS
   ORDER BY USER_NAME, AUDIT_OPTION
";

      print <<"EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <FORM METHOD=POST ACTION=$scriptname>
    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
    <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Remove marked audits">
    <P>
    <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
    <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
    <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
    <INPUT TYPE="HIDDEN" NAME="arg" VALUE="removestmtaudits">
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Mark</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Audit option</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Username</TH>
EOF

      $cursor = $dbh->prepare($sql);
      $cursor->execute;

      while (($audit_option,$username) = $cursor->fetchrow_array) {
         $new_audit_option = $audit_option;
         $new_audit_option =~ s/ /+/g;
         print <<"EOF";
        <TR>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><INPUT TYPE=CHECKBOX NAME=removeaudit_$new_audit_option~$username></TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$username</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$audit_option</TD>
        </TR>
EOF
   }
      $cursor->finish;
      print <<"EOF";
      </TABLE>
    </TD>
  </TR>
  </FORM>
</TABLE>
EOF
   } else {

      message("There are no SQL statement / System audits enabled.");
   }

   $sql = "$copyright
SELECT
   COUNT(*)
FROM DBA_OBJ_AUDIT_OPTS
WHERE ALT != '-/-'
OR AUD != '-/-'
OR COM != '-/-'
OR DEL != '-/-'
OR GRA != '-/-'
OR IND != '-/-'
OR INS != '-/-'
OR LOC != '-/-'
OR REN != '-/-'
OR SEL != '-/-'
OR UPD != '-/-'
OR REF != '-/-'
OR EXE != '-/-'
";

   $sql = "$copyright
SELECT
   COUNT(*)
FROM DBA_OBJ_AUDIT_OPTS
WHERE ALT != '-/-'
OR AUD != '-/-'
OR COM != '-/-'
OR DEL != '-/-'
OR GRA != '-/-'
OR IND != '-/-'
OR INS != '-/-'
OR LOC != '-/-'
OR REN != '-/-'
OR SEL != '-/-'
OR UPD != '-/-'
OR EXE != '-/-'
OR CRE != '-/-'
OR REA != '-/-'
OR WRI != '-/-'
" if ($oracle8);

   $cursor = $dbh->prepare($sql);
   $cursor->execute;

   $count = $cursor->fetchrow_array;

   $cursor->finish;

   if ($count) {

      text("Schema object audits");

      $sql = "$copyright
SELECT
   OBJECT_NAME         \"Object name\",
   OBJECT_TYPE         \"Object type\",
   OWNER               \"Owner\"
FROM DBA_OBJ_AUDIT_OPTS
WHERE ALT != '-/-'
OR AUD != '-/-'
OR COM != '-/-'
OR DEL != '-/-'
OR GRA != '-/-'
OR IND != '-/-'
OR INS != '-/-'
OR LOC != '-/-'
OR REN != '-/-'
OR SEL != '-/-'
OR UPD != '-/-'
OR REF != '-/-'
OR EXE != '-/-'
ORDER BY OWNER
";

      $sql = "$copyright
SELECT
   OBJECT_NAME         \"Object name\",
   OBJECT_TYPE         \"Object type\",
   OWNER               \"Owner\"
FROM DBA_OBJ_AUDIT_OPTS
WHERE ALT != '-/-'
OR AUD != '-/-'
OR COM != '-/-'
OR DEL != '-/-'
OR GRA != '-/-'
OR IND != '-/-'
OR INS != '-/-'
OR LOC != '-/-'
OR REN != '-/-'
OR SEL != '-/-'
OR UPD != '-/-'
OR EXE != '-/-'
OR CRE != '-/-'
OR REA != '-/-'
OR WRI != '-/-'
ORDER BY OWNER
" if ($oracle8);

      print <<"EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <FORM METHOD=POST ACTION=$scriptname>
    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
    <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Remove marked audits">
    <P>
    <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
    <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
    <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
    <INPUT TYPE="HIDDEN" NAME="arg" VALUE="removeobjaudits">
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Mark</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Object name</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Object type</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Owner</TH>
EOF

      $cursor = $dbh->prepare($sql);
      $cursor->execute;

      while (($object_name,$object_type,$owner) = $cursor->fetchrow_array) {
         print <<"EOF";
        <TR>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><INPUT TYPE=CHECKBOX NAME=removeaudit_$owner~$object_name></TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$object_name</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$object_type</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$owner</TD>
        </TR>
EOF
   }
      $cursor->finish;
      print <<"EOF";
      </TABLE>
    </TD>
  </TR>
  </FORM>
</TABLE>
EOF
   } else {

      message("There are no individual schema object audits enabled.");
   }

   logit("Exit subroutine auditList");

}

sub shortMenu {

   logit("Enter subroutine shortMenu");

   my $schema = shift;
   my ($bgline,$key);

   $bgline = "<BODY LINK=$linkcolor ALINK=$linkcolor VLINK=$linkcolor BGCOLOR=$bgcolor>\n";

   if ($menuimage) {
      if ((-e "$ENV{'DOCUMENT_ROOT'}/$menuimage") && (-r "$ENV{'DOCUMENT_ROOT'}/$menuimage")) {
         logit("   Menu image is $ENV{'DOCUMENT_ROOT'}/$menuimage and is readable");
         $bgline = "<BODY LINK=$linkcolor ALINK=$linkcolor VLINK=$linkcolor BACKGROUND=$menuimage>\n";
      }
   }


   print <<"EOF";
Content-type: Text/html\n\n
<HTML>
<STYLE TYPE="text/css">
        <!-- A{text-decoration: none;} A:link{color: $linkcolor;}A:visited{color: $linkcolor;} -->
</STYLE>
$bgline
<FONT FACE="" SIZE="2" COLOR="$fontcolor">
<CENTER>
<P>
<TABLE "WIDTH=100%">
  <TR WIDTH="100%">
    <TD VALIGN="TOP">
EOF
Button("$scriptname?database=$database&object_type=WORKSHEET&schema=$schema TARGET=body","SQL Worksheet","$headingcolor");
Button("$scriptname?database=$database&object_type=RMANMONITOR TARGET=body","Monitor RMAN","$headingcolor");

print <<"EOF";
    </TD>
  </TR>
</TABLE>
EOF

   logit("Exit subroutine shortMenu");

   exit;

}

sub showMenu {

   logit("Enter subroutine showMenu");

   my $schema = shift;
   my ($bgline,$key);

   $bgline = "<BODY LINK=$linkcolor ALINK=$linkcolor VLINK=$linkcolor BGCOLOR=$bgcolor>\n";

   if ($menuimage) {
      if ((-e "$ENV{'DOCUMENT_ROOT'}/$menuimage") && (-r "$ENV{'DOCUMENT_ROOT'}/$menuimage")) {
         logit("   Menu image is $ENV{'DOCUMENT_ROOT'}/$menuimage and is readable");
         $bgline = "<BODY LINK=$linkcolor ALINK=$linkcolor VLINK=$linkcolor BACKGROUND=$menuimage>\n";
      }
   }

   print <<"EOF";
Content-type: Text/html\n\n
<HTML>
<STYLE TYPE="text/css">
        <!-- A{text-decoration: none;} A:link{color: $linkcolor;}A:visited{color: $linkcolor;} -->
</STYLE>
<HEAD>
</HEAD>
$bgline
<FONT FACE="" SIZE="2" COLOR="$fontcolor">
<CENTER>
<P>
<TABLE "WIDTH=100%">
  <TR WIDTH="100%">
    <TD VALIGN="TOP">
EOF
Button("$scriptname?database=$database&object_type=MYORACLETOOL TARGET=body","My Oracletool","$headingcolor");
if (my $ownerid = PeoplesoftInstalled()) {
   Button("$scriptname?database=$database&object_type=PSOFTMENU TARGET=body","Peoplesoft","$headingcolor");
}
Button("$scriptname?database=$database&object_type=LISTUSERS TARGET=body","Schema list","$headingcolor");
Button("$scriptname?database=$database&object_type=SESSIONMENU TARGET=body","Session info","$headingcolor");
if ($oracle10) {
   if (usesASM()) {
      Button("$scriptname?database=$database&object_type=ASM TARGET=body","ASM","$headingcolor");
   }
}
Button("$scriptname?database=$database&object_type=TABLESPACES TARGET=body","Tablespaces","$headingcolor");
Button("$scriptname?database=$database&object_type=DATAFILES TARGET=body","Datafiles","$headingcolor");
Button("$scriptname?database=$database&object_type=REDOLOGS TARGET=body","Redo / Flashback","$headingcolor");
Button("$scriptname?database=$database&object_type=ROLLBACKMENU TARGET=body","Rollback segs","$headingcolor");
Button("$scriptname?database=$database&object_type=PERFMENU TARGET=body","Perf / memory","$headingcolor");
Button("$scriptname?database=$database&object_type=CONTENTION TARGET=body","Locks / contends","$headingcolor");
Button("$scriptname?database=$database&object_type=EXPLAIN TARGET=body","Explain plan","$headingcolor");
Button("$scriptname?database=$database&object_type=WORKSHEET&schema=$schema TARGET=body","SQL Worksheet","$headingcolor");
Button("$scriptname?database=$database&object_type=SECURITY TARGET=body","Security","$headingcolor");
Button("$scriptname?database=$database&object_type=CONTROLFILES TARGET=body","Controlfiles","$headingcolor");
Button("$scriptname?database=$database&object_type=PARAMETERS TARGET=body","Init parameters","$headingcolor");
if ($notoracle7) {
   if (repmaster()) {
      Button("$scriptname?database=$database&object_type=REPMASTER TARGET=body","Replication (M)","$headingcolor");
   }
   if (repsnapshot()) {
      Button("$scriptname?database=$database&object_type=REFRESHGROUPS TARGET=body","Replication (S)","$headingcolor");
   }
   if (advrep()) {
      Button("$scriptname?database=$database&object_type=ADVREP TARGET=body","Advanced Replication","$headingcolor");
   }
}
if (parallel()) {
   Button("$scriptname?database=$database&object_type=OPSMENU TARGET=body","RAC specific","$headingcolor");
}
if ($notoracle7) {
   if ((backupsFound()) || (rmanCatalogExists())) {
      Button("$scriptname?database=$database&object_type=BACKUPMENU TARGET=body","RMAN","$headingcolor");
   }
}
if ($oraclei && statsPackInstalled()) {
   Button("$scriptname?database=$database&object_type=STATSPACKMENU TARGET=body","Statspack","$headingcolor");
}
Button("$scriptname?database=$database&object_type=RECENTEVENTS TARGET=body","Recent events","$headingcolor");
Button("$scriptname?database=$database&object_type=PREFMENU TARGET=body","Preferences","$headingcolor");
Button("$scriptname?database=$database&object_type=TASKMENU TARGET=body","DB Admin","$headingcolor");
Button("$scriptname TARGET=_top","Change connection","$headingcolor");
   print <<"EOF";
      <FORM METHOD=POST ACTION=$scriptname TARGET=body>
        <INPUT TYPE="TEXT" NAME="arg" SIZE="10">&nbsp;&nbsp;<A HREF=$scriptname?database=$database&object_type=SEARCHHELP TARGET=body><FONT FACE="$font" SIZE="$fontsize" COLOR="$fontcolor">?</FONT></a>
        <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
        <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="OBJECTSEARCH">
        <INPUT TYPE="SUBMIT" VALUE="Search">
      </FORM>
EOF
# Add plugins if found
foreach $key(keys %plugins) {
   Button("$plugins{$key} TARGET=body","$key","$headingcolor");
}
Button("$scriptname?database=About_oracletool TARGET=body","About","$headingcolor");
Button("","<FONT COLOR=RED>DEBUG ON</FONT>","$headingcolor") if $debug;
Button("","<FONT COLOR=RED>LOGGING</FONT>","$headingcolor") if $logging;
print <<"EOF";
    </TD>
  </TR>
</TABLE>
EOF

   logit("Exit subroutine showMenu");

exit;

}

sub usesASM {

   logit("Enter subroutine usesASM");

   my ($count);

   $count = recordCount($dbh,"Select name from v\$asm_diskgroup");
   if ($count) {
      logit("  Looks like we're using ASM for storage");
   } else {
      logit("  No ASM in use here.");
   }
   return($count);

   logit("Exit subroutine usesASM");

}

sub psoftMenu {

   logit("Enter subroutine psoftMenu");

   my ($psdbowner,$sql,$cursor,$count,$oprids,$clients,$mostrecent,$earliest);
   my ($oprid,$osid,$hostname,$appserver,$program,$foo,$sid,$serial,$client_info,$module);
   my ($text,$link,$infotext,$oprdefndesc,$sql1,$cursor1,$status,$sql_text);

   if ($nls_date_format) {
      $dbh->do("Alter session set nls_date_format = '$nls_date_format'");
   }

   refreshButton();

   $psdbowner = PeoplesoftInstalled();

   # Check for a PSACCESSLOG table
   $count = recordCount($dbh,"SELECT TABLE_NAME FROM DBA_TABLES WHERE OWNER = '$psdbowner' AND TABLE_NAME = 'PSACCESSLOG'");

   # If PSACCESSLOG table exists
   if ($count) {

      # Get a record count (Number of logins / logouts per instance)
      $sql = "Select count(*) from $psdbowner.psaccesslog where LOGINDTTM > sysdate-30";
      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      $count = $cursor->fetchrow_array;
      $cursor->finish;

      # If number of logins is non-zero
      if ($count) {

         # Get the earliest recorded login time
         $sql = "Select min(LOGINDTTM) from $psdbowner.psaccesslog";
         $cursor = $dbh->prepare($sql);
         $cursor->execute;
         $earliest = $cursor->fetchrow_array;
         $cursor->finish;

         # Get the most recent recorded login time
         $sql = "Select max(LOGINDTTM) from $psdbowner.psaccesslog";
         $cursor = $dbh->prepare($sql);
         $cursor->execute;
         $mostrecent = $cursor->fetchrow_array;
         $cursor->finish;

         # Get the number of distinct client IP's
         $sql = "Select count(distinct logipaddress) from $psdbowner.psaccesslog";
         $cursor = $dbh->prepare($sql);
         $cursor->execute;
         $clients = $cursor->fetchrow_array;
         $cursor->finish;

         # Get the number of distinct OPRID's
         $sql = "Select count(distinct oprid) from $psdbowner.psaccesslog";
         $cursor = $dbh->prepare($sql);
         $cursor->execute;
         $oprids = $cursor->fetchrow_array;
         $cursor->finish;
         $sql = "
SELECT 
   TO_CHAR($count,'999,999,999,999')		\"Login count\",
   '$earliest'					\"Least recent login\",
   '$mostrecent'				\"Most recent login\",
   TO_CHAR($clients,'999,999,999,999')		\"Distinct clients#\",
   TO_CHAR($oprids,'999,999,999,999')		\"Distinct OPRID's#\"
FROM DUAL";
   
         $text = "Login information, last 30 days.";
         $link = "";
         $infotext = "";
         DisplayTable($sql,$text,$link,$infotext);

      } else {
         message("There is no PSACCESSLOG table for this instance.");
      }
   }

#   $sql = "Select sysdate from dual";
#   $text = "Current date";
#   $link = "";
#   $infotext = "";
#   DisplayTable($sql,$text,$link,$infotext);

      text("Peoplesoft related session information.");

      print << "EOF";
<P>
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>SID</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Username</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>OPRID</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Status</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>SQL text</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Hostname</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Appserver</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Program</TH>
EOF

   $sql = "
SELECT
   SID,
   SERIAL#,
   STATUS,
   CLIENT_INFO,
   MODULE
FROM V\$SESSION
   WHERE USERNAME = '$psdbowner'
   AND CLIENT_INFO IS NOT NULL
ORDER BY STATUS
";

   $cursor = $dbh->prepare($sql) or logit ("Error: $DBI::errstr");
   $cursor->execute;
   while (($sid,$serial,$status,$client_info,$module) = $cursor->fetchrow_array) {
      ($oprid,$osid,$hostname,$appserver,$program,$foo) = split(",",$client_info);
      $sql1 = 
"SELECT 
   OPRDEFNDESC
FROM $psdbowner.PSOPRDEFN
   WHERE OPRID = '$oprid'
";
      $cursor1 = $dbh->prepare($sql1) or logit ("Error: $DBI::errstr");
      $cursor1->execute or logit ("Error: $DBI::errstr");
      $oprdefndesc = $cursor1->fetchrow_array;
      $cursor1->finish;
#      $oprdefndesc = "None provided" if ($oprdefndesc eq " ");
      $sql1 = "
SELECT
   NVL(VST.SQL_TEXT,'None available')
FROM V\$SESSION VS,
     V\$SQLTEXT VST
   WHERE VS.SID=$sid
   AND VS.SERIAL#=$serial
   AND VS.SQL_ADDRESS = VST.ADDRESS (+)
   AND VST.PIECE (+) = 0;
      $cursor1 = $dbh->prepare($sql1);
      $cursor1->execute;
      $sql_text=$cursor1->fetchrow_array;
      $cursor1->finish
";
      logit("Info is: $sid-$oprdefndesc-$oprid-$status-$sql_text-$hostname-$appserver-$program");
      print <<"EOF";
        <TR>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=SESSIONINFO&user=$psdbowner&sid=$sid>$sid</A></TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$oprdefndesc</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$oprid</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$status</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$sql_text</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$hostname</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$appserver</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$program</TD>
        </TR>
EOF
#      logit("Client info: $oprid-$osid-$hostname-$appserver-$program-$foo");
#      logit("Session info: $sid,$serial,$status,$module");
#      logit("Username is ~$oprdefndesc~");
   }
   $cursor->finish;

   print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF

#   $sql = "
#SELECT 
#   A.PRCSNAME						\"Job name\",
#   A.RUNCNTLID						\"Run control ID\",
#   A.PRCSTYPE						\"Type\",
#   A.OPRID						\"OprID\",
#   B.OPRDEFNDESC					\"User name\",
#   B.EMAILID						\"Email\",
#   TO_CHAR(TRUNC(((86400*(SYSDATE-A.RUNDTTM))/60)/60)-(TRUNC((((86400*(SYSDATE-A.RUNDTTM))/60)/60)/24)),'00')||':'||TO_CHAR(TRUNC((86400*(SYSDATE-A.RUNDTTM))/60)-60*(TRUNC(((86400*(SYSDATE-A.RUNDTTM))/60)/60)),'00')||':'||TO_CHAR(TRUNC(86400*(SYSDATE-A.RUNDTTM))-60*(TRUNC((86400*(SYSDATE-A.RUNDTTM))/60)),'00') \"Elapsed (HH:MI:SS)\",
#   TO_CHAR(A.RQSTDTTM,'Day, Mon DD HH24:MI:SS')		\"Request time\",
#   TO_CHAR(A.RUNDTTM,'Day, Mon DD HH24:MI:SS')		\"Start time\",
#   TO_CHAR(A.LASTUPDDTTM,'Day, Mon DD HH24:MI:SS')	\"Last update\"
#FROM $psdbowner.PSPRCSRQST A, $psdbowner.PSOPRDEFN B
#   WHERE A.ENDDTTM IS NULL
#   AND A.OPRID = B.OPRID";

##   WHERE A.RUNDTTM < SYSDATE

#   $text = "Running jobs";
#   $link = "";
#   $infotext = "There are no jobs running at this time";
#   DisplayTable($sql,$text,$link,$infotext);

#   $sql = "
#SELECT 
#   A.PRCSNAME						\"Job name\",
#   A.RUNCNTLID						\"Run control ID\",
#   A.PRCSTYPE						\"Type\",
#   A.OPRID						\"OprID\",
#   B.OPRDEFNDESC					\"User name\",
#   B.EMAILID						\"Email\",
#   TO_CHAR(A.RQSTDTTM,'Day, Mon DD HH24:MI:SS')		\"Request time\",
#   TO_CHAR(A.RUNDTTM,'Day, Mon DD HH24:MI:SS')		\"Start time\"
#FROM $psdbowner.PSPRCSRQST A, $psdbowner.PSOPRDEFN B
#   WHERE A.RUNDTTM > SYSDATE
#   AND A.ENDDTTM IS NULL
#   AND A.OPRID = B.OPRID";
   
#   $text = "Scheduled jobs";
#   $link = "";
#   $infotext = "There are no jobs scheduled at this time";
#   DisplayTable($sql,$text,$link,$infotext);

#   $sql = "
#SELECT 
#   A.PRCSNAME						\"Job name\",
#   A.RUNCNTLID						\"Run control ID\",
#   A.PRCSTYPE						\"Type\",
#   A.OPRID						\"OprID\",
#   B.OPRDEFNDESC					\"User name\",
#   B.EMAILID						\"Email\",
#   TO_CHAR(TRUNC(((86400*(A.ENDDTTM-A.RUNDTTM))/60)/60)-(TRUNC((((86400*(A.ENDDTTM-A.RUNDTTM))/60)/60)/24)),'00')||':'||TO_CHAR(TRUNC((86400*(A.ENDDTTM-A.RUNDTTM))/60)-60*(TRUNC(((86400*(A.ENDDTTM-A.RUNDTTM))/60)/60)),'00')||':'||TO_CHAR(TRUNC(86400*(A.ENDDTTM-A.RUNDTTM))-60*(TRUNC((86400*(A.ENDDTTM-A.RUNDTTM))/60)),'00') \"Elapsed (HH:MI:SS)\",
#   TO_CHAR(A.RUNDTTM,'Day, Mon DD HH24:MI:SS')		\"Start time\",
#   TO_CHAR(A.ENDDTTM,'Day, Mon DD HH24:MI:SS')		\"Completion time\" 
#FROM $psdbowner.PSPRCSRQST A, $psdbowner.PSOPRDEFN B
#   WHERE A.ENDDTTM IS NOT NULL
#   AND A.ENDDTTM > SYSDATE - .5
#   AND A.OPRID = B.OPRID
#   ORDER BY A.ENDDTTM DESC";
   
#   $text = "Jobs completed last 12 hours";
#   $link = "";
#   $infotext = "No jobs completed in the last 12 hours";
#   DisplayTable($sql,$text,$link,$infotext);
   
}

sub PeoplesoftInstalled {

   logit("Enter subroutine PeoplesoftInstalled");

   my $count = recordCount($dbh,"SELECT TABLE_NAME FROM DBA_TABLES WHERE OWNER = 'PS' AND TABLE_NAME = 'PSDBOWNER'");

   if ($count) {
      my $sql = "SELECT OWNERID FROM PS.PSDBOWNER";
      my $cursor = $dbh->prepare($sql) or logit("   Error: $DBI::errstr");
      $cursor->execute or logit("   Error: $DBI::errstr");
      my $ownerid = $cursor->fetchrow_array;
      $cursor->finish;
      return($ownerid);
   } else {
      return(0);
   }
}

sub ErrorPage {

   logit("Enter subroutine ErrorPage");

# Usage: ErrorPage ($message);

   my $message          = shift;

   my $bgline = "<BODY BGCOLOR=$bgcolor>\n";

   if ($menuimage) {
      if ((-e "$ENV{'DOCUMENT_ROOT'}/$menuimage") && (-r "$ENV{'DOCUMENT_ROOT'}/$menuimage")) {
         logit("   Menu image is $ENV{'DOCUMENT_ROOT'}/$menuimage and is readable");
         $bgline = "<BODY BACKGROUND=$menuimage>\n";
      }
   }

print <<EOF;
Content-type: Text/html\n\n
<HTML>
  <HEAD>
    <TITLE>Error!</TITLE>
  </HEAD>
      $bgline
      <FONT FACE="$font" SIZE="$fontsize" COLOR="$fontcolor">
      <CENTER>
      $message
      </CENTER>
  </BODY
</HTML>
EOF

   logit("Exit subroutine ErrorPage");

exit(1);
}

sub TempPage {

   logit("Enter subroutine TempPage");

# Usage: TempPage ($message,$duration,$url);

   my $message  = shift;
   my $duration = shift;
   my $url      = shift;

   my $bgline = "<BODY BGCOLOR=$bgcolor>\n";

   if ($menuimage) {
      if ((-e "$ENV{'DOCUMENT_ROOT'}/$menuimage") && (-r "$ENV{'DOCUMENT_ROOT'}/$menuimage")) {
         logit("   Menu image is $ENV{'DOCUMENT_ROOT'}/$menuimage and is readable");
         $bgline = "<BODY BACKGROUND=$menuimage>\n";
      }
   }

print <<EOF;
Content-type: Text/html\n\n
<HTML>
  <HEAD>
    <TITLE>Notice!</TITLE>
    <META HTTP-EQUIV="Refresh" Content="$duration;URL=$url">
  </HEAD>
    $bgline
    <FONT FACE="$font" SIZE="$fontsize" COLOR="$fontcolor">
    <CENTER>
      $message
    </CENTER
  </BODY
</HTML>
EOF

   logit("Exit subroutine TempPage");

}

sub getDBblocksize {

   logit("Enter subroutine getDBblocksize");

# Find out the database block size

   my $sql = "$copyright
SELECT VALUE
   FROM V\$PARAMETER
WHERE NAME = 'db_block_size'
";

   my $cursor = $dbh->prepare($sql);
   $cursor->execute;
   my $db_block_size = $cursor->fetchrow_array;
   $cursor->finish;
   logit("   DB_BLOCK_SIZE = $db_block_size");
   logit("Exit subroutine getDBblocksize");
   return ($db_block_size);


}

sub getBanner {

   logit("Enter subroutine getBanner");

   my ($banner,$port,$foo,$sql,$cursor);

# Get the hostname

   $hostname = "";

   if ($notoracle7) {

     $sql = "
SELECT
   HOST_NAME
FROM V\$INSTANCE
";
      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      $hostname = $cursor->fetchrow_array;
      $cursor->finish;
   }

# Get the oracle version info

   $sql = "$copyright
SELECT BANNER 
   FROM V\$VERSION
WHERE BANNER LIKE 'Oracle%'
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $banner = $cursor->fetchrow_array;
   $cursor->finish;

# Add to the banner PORT information. (OS, hardware)

   $sql = "$copyright
BEGIN
   :port := SYS.DBMS_UTILITY.PORT_STRING;
END;
";
   $cursor = $dbh->prepare($sql);
   $cursor->bind_param_inout(":port", \$port, 1);
   $cursor->execute;
   $banner = "$banner ($port)";
   $cursor->finish;

   $sql = "$copyright
SELECT
   TO_CHAR(TO_DATE(D.VALUE,'J'),'Day, Month DD, YYYY')||' -  '||
   TO_CHAR(TO_DATE(S.VALUE,'sssss'),'HH24:MI:SS')
FROM V\$INSTANCE D, V\$INSTANCE S
   WHERE D.KEY = 'STARTUP TIME - JULIAN'
   AND S.key = 'STARTUP TIME - SECONDS'
" if ($oracle7);

   $sql = "$copyright
SELECT
   TO_CHAR(STARTUP_TIME,'Day, Month DD, YYYY -  HH24:MI:SS')
FROM V\$INSTANCE
" if ($notoracle7);

   $cursor = $dbh->prepare($sql) or text("$DBI::errstr");;
   $cursor->execute;
   $foo = $cursor->fetchrow_array;
   $cursor->finish;

   $banner = "$banner<BR>Instance started on $foo<BR>";

   logit("Exit subroutine getBanner");

   return($banner);
}

sub showTSgraph {

   logit("Enter subroutine showTSgraph");

   my ($sql,$text,$link,$cursor,$tablespace,$bytesalloc,$bytesused,$bytesfree,$pctused,$pctfree);
   my ($sortfield,$highlight,$color,$command,$refreshrate);

   $sortfield	= $query->param('sortfield') || "1";
   $command	= $query->param('command') || "1";
   $refreshrate	= $query->param('refreshrate') || "10";
   $highlight = "#FFFFC6";

   unless ($norefreshbutton) {

      print <<"EOF";
  <FORM METHOD="POST" ACTION="$scriptname">
    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
    <INPUT TYPE=HIDDEN NAME=database    VALUE=$database>
    <INPUT TYPE=HIDDEN NAME=object_type VALUE=$object_type>
    <INPUT TYPE=HIDDEN NAME=arg         VALUE=$object_name>
    <INPUT TYPE=HIDDEN NAME=refreshrate VALUE=$refreshrate>
    <INPUT TYPE=HIDDEN NAME=sortfield   VALUE=$sortfield>
    <INPUT TYPE=SUBMIT NAME=foobar      VALUE=\"AutoRefresh ($refreshrate)\">
  </FORM>
  <P>
EOF

   }

# Show a graph of tablespace usage based on free space.

# Print the page header

   print <<"EOF";
</CENTER>
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0 ALIGN=CENTER>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
EOF
if ($sortfield eq "1") {
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&sortfield=1&command=$command>Tablespace name</A></TH>\n";

if ($sortfield eq "2") {
      $sortfield = "2 DESC";
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&sortfield=2&command=$command>Bytes allocated</A></TH>\n";

if ($sortfield eq "3") {
      $sortfield = "3 DESC";
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&sortfield=3&command=$command>Bytes used</A></TH>\n";

if ($sortfield eq "4") {
      $sortfield = "4 ASC";
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&sortfield=4&command=$command>Bytes free</A></TH>\n";

if ($sortfield eq "5") {
      $sortfield = "5 DESC";
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&sortfield=5&command=$command>%Used graph</A></TH>\n";

if ($sortfield eq "6") {
      $sortfield = "5 DESC";
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&sortfield=6&command=$command>Percent used</A></TH>\n";

if ($sortfield eq "7") {
      $sortfield = "6 ASC";
      $color = $highlight;
   } else {
      $color = $headingcolor;
   }
   print "         <TH BGCOLOR='$color' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'><A HREF=$scriptname?database=$database&object_type=$object_type&sortfield=7&command=$command>Percent free</A></TH>\n";

   $sql = "$copyright
SELECT
   DF.TABLESPACE_NAME                                           \"Tablespace name\",
   TO_CHAR(DF.BYTES,'999,999,999,999,999,999')                          \"Bytes allocated\",
   NVL(TO_CHAR(DF.BYTES-SUM(FS.BYTES),'999,999,999,999,999,999'),
        TO_CHAR(DF.BYTES,'999,999,999,999,999,999'))                    \"Bytes used\",
   NVL(TO_CHAR(SUM(FS.BYTES),'999,999,999,999,999,999'),0)              \"Bytes free\",
   NVL(ROUND((DF.BYTES-SUM(FS.BYTES))*100/DF.BYTES),100)        \"Percent used\",
   NVL(ROUND(SUM(FS.BYTES)*100/DF.BYTES),0)                     \"Percent free\"
FROM DBA_FREE_SPACE FS,
   (SELECT TABLESPACE_NAME, SUM(BYTES) BYTES FROM DBA_DATA_FILES GROUP BY
TABLESPACE_NAME ) DF
WHERE FS.TABLESPACE_NAME (+) = DF.TABLESPACE_NAME
GROUP BY DF.TABLESPACE_NAME, DF.BYTES
ORDER BY $sortfield
";

   # Added for the display of tablespaces which utilize TEMP files.

   $sql = "$copyright
SELECT
   DF.TABLESPACE_NAME                                           \"Tablespace name\",
   TO_CHAR(DF.BYTES,'999,999,999,999,999,999')                          \"Bytes allocated\",
   NVL(TO_CHAR(DF.BYTES-SUM(FS.BYTES),'999,999,999,999,999,999'),
        TO_CHAR(DF.BYTES,'999,999,999,999,999,999'))                    \"Bytes used\",
   NVL(TO_CHAR(SUM(FS.BYTES),'999,999,999,999,999,999'),0)              \"Bytes free\",
   NVL(ROUND((DF.BYTES-SUM(FS.BYTES))*100/DF.BYTES),100)        \"Percent used\",
   NVL(ROUND(SUM(FS.BYTES)*100/DF.BYTES),0)                     \"Percent free\"
FROM DBA_FREE_SPACE FS,
   (SELECT TABLESPACE_NAME, SUM(BYTES) BYTES FROM DBA_DATA_FILES GROUP BY
TABLESPACE_NAME ) DF
WHERE FS.TABLESPACE_NAME (+) = DF.TABLESPACE_NAME
GROUP BY DF.TABLESPACE_NAME, DF.BYTES
UNION ALL
SELECT
   DF.TABLESPACE_NAME                                           \"Tablespace name\",
   TO_CHAR(DF.BYTES,'999,999,999,999,999,999')                          \"Bytes allocated\",
   NVL(TO_CHAR(SUM(FS.BYTES_USED),'999,999,999,999,999,999'),0)         \"Bytes used\",
   NVL(TO_CHAR(DF.BYTES-SUM(FS.BYTES_USED),'999,999,999,999,999,999'),
        TO_CHAR(DF.BYTES,'999,999,999,999,999,999'))                    \"Bytes free\",
   NVL(ROUND(SUM(FS.BYTES_USED)*100/DF.BYTES),0)           \"Percent used\",
   NVL(ROUND((DF.BYTES-SUM(FS.BYTES_USED))*100/DF.BYTES),100) \"Percent free\"
FROM V\$TEMP_EXTENT_POOL FS,
   (SELECT TABLESPACE_NAME, SUM(BYTES) BYTES FROM DBA_TEMP_FILES GROUP BY
TABLESPACE_NAME ) DF
WHERE FS.TABLESPACE_NAME (+) = DF.TABLESPACE_NAME
GROUP BY DF.TABLESPACE_NAME, DF.BYTES
ORDER BY $sortfield
" if ($oraclei);

# Get the space allocation info

   $cursor=$dbh->prepare($sql);
   $cursor->execute;
   while (($tablespace,$bytesalloc,$bytesused,$bytesfree,$pctused,$pctfree) = $cursor->fetchrow_array ) {
      $bytesalloc=commify($bytesalloc);
      $bytesused=commify($bytesused);
      $bytesfree=commify($bytesfree);
      print <<"EOF";
        <TR>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=TSINFO&arg=$tablespace>$tablespace</A></TD>
          <TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$bytesalloc</TD>
          <TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$bytesused</TD>
          <TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$bytesfree</TD>
          <TD BGCOLOR='$cellcolor' WIDTH=100>
            <TABLE>
              <TR>
                <TD WIDTH=$pctused BGCOLOR='$linkcolor'><BR></TD>
              </TR>
            </TABLE>
          </TD>
          <TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$pctused%</TD>
          <TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$pctfree%</TD>
        </TR>
EOF
   }
   $cursor->finish;
print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF

   logit("Exit subroutine showTSgraph");

}

sub traceSession {

   logit("Enter subroutine traceSession");

   my ($sql,$sid,$serial,$trace,$boolean,$tracemsg);

   $sid		= $query->param('sid');
   $serial	= $query->param('serial');
   $trace	= $query->param('trace');
   $boolean	= 1;

   if ($trace eq "enable") {
      $trace = "ENABLE";
      $tracemsg = "enabled";
   }
   if ($trace eq "disable") {
      $trace = "DISABLE";
      $tracemsg = "disabled";
   }

      $sql = "
BEGIN
   DBMS_MONITOR.SESSION_TRACE_$trace(?,?);
END;
";

   logit("   Preparing - SID = $sid SERIAL = $serial");
   $cursor = $dbh->prepare($sql) || logit("$DBI::errstr");
   logit("   Error: $DBI::errstr") if ($DBI::errstr);
   $cursor->bind_param(1,$sid);
   logit("   Error: $DBI::errstr") if ($DBI::errstr);
   $cursor->bind_param(2,$serial);
   logit("   Error: $DBI::errstr") if ($DBI::errstr);
   logit("   executing");
   $cursor->execute;
   logit("   Error: $DBI::errstr") if ($DBI::errstr);
   $cursor->finish;
   logit("   Error: $DBI::errstr") if ($DBI::errstr);
   logit($sql);

   #message("SQL trace $tracemsg for SID $sid Serial# $serial<P>Check for trace file in user_dump_dest.");
  
   #$sql = "Select * from v\$session where sid=$sid and serial# = $serial";
   
   #my $text = "Test";
   #my $link = "";
   #my $infotext = "";
   #DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine traceSession");

   sessionInfo();

}

sub killSession {

   logit("Enter subroutine killSession");

   my ($sql);

   $sql = "Alter system kill session '$object_name,$schema'";
  
   runSQL($dbh,$sql);

   logit("Exit subroutine killSession");

}

sub showSessionstats {

   logit("Enter subroutine showSessionstats");

   my ($sql,$text,$link,$infotext,$count,$cursor,$open_cursors,$event);
##   my ($refreshrate);

   refreshButton();

##   $refreshrate	= $query->param('refreshrate') || "10";
##   $sid		= $query->param('sid');
##   $serial	= $query->param('serial');

##   unless ($norefreshbutton) {

##      logit("   SID $sid Serial $serial Schema $schema Database $database ");

##      print <<"EOF";
##  <FORM METHOD="POST" ACTION="$scriptname">
##    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
##    <INPUT TYPE=HIDDEN NAME=database    VALUE=$database>
##    <INPUT TYPE=HIDDEN NAME=object_type VALUE=SESSIONSTATS>
##    <INPUT TYPE=HIDDEN NAME=refreshrate VALUE=$refreshrate>
##    <INPUT TYPE=HIDDEN NAME=schema	VALUE=$schema>
##    <INPUT TYPE=HIDDEN NAME=sid		VALUE=$sid>
##    <INPUT TYPE=HIDDEN NAME=serial	VALUE=$serial>
##    <INPUT TYPE=SUBMIT NAME=foobar      VALUE=\"AutoRefresh ($refreshrate)\">
##  </FORM>
##  <P>
##EOF
##
##  }

   $sql = "$copyright
SELECT 
   SEQ#							\"Seq#\",
   EVENT						\"Event\",
   SECONDS_IN_WAIT					\"Seconds waiting\"
FROM V\$SESSION_WAIT
   WHERE SID = $schema
";
   
   $text = "Current session wait information.";
   $link = "";
   $infotext = "No info in V\$SESSION_WAIT.";
   DisplayTable($sql,$text,$link,$infotext);

   $sql = "
SELECT
   EVENT
FROM V\$SESSION_WAIT
   WHERE SID = $schema
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $event = $cursor->fetchrow_array;
   $cursor->finish;

   if ($event eq "latch free") {
      logit("   Session $schema waiting on latch free, gathering additional info..");
   }

   $sql = "$copyright
SELECT
   EVENT					\"Event\",
   TO_CHAR(TOTAL_WAITS,'999,999,999,999')	\"Total waits\",
   TO_CHAR(TOTAL_TIMEOUTS,'999,999,999,999')	\"Total timeouts\",
   TO_CHAR((TIME_WAITED/100),'999,999,999,999')	\"Time waited (seconds)\",
   TO_CHAR(((TIME_WAITED/100)/60),'999,999,999,999')	\"Time waited (minutes)\"
FROM V\$SESSION_EVENT
   WHERE SID = $schema
ORDER BY 4 DESC
";
   
   $text = "Session event wait information, since session inception.";
   $link = "";
   $infotext = "No info in V\$SESSION_EVENT.";
   DisplayTable($sql,$text,$link,$infotext);

   $sql = "$copyright
SELECT 
   TO_CHAR(BLOCK_GETS,'999,999,999,999')		\"Block gets\",
   TO_CHAR(CONSISTENT_GETS,'999,999,999,999')		\"Consistent gets\",
   TO_CHAR(PHYSICAL_READS,'999,999,999,999')		\"Physical reads\",
   TO_CHAR(BLOCK_CHANGES,'999,999,999,999')		\"Block changes\",
   TO_CHAR(CONSISTENT_CHANGES,'999,999,999,999')	\"Consistent changes\"
FROM V\$SESS_IO
   WHERE SID = $schema
";

   $text = "Session I/O information.";
   $link = "";
   $infotext = "No info in V\$SESS_IO.";
   DisplayTable($sql,$text,$link,$infotext);

# Display output from V$SESSION_LONGOPS if Oracle8

   if ($oracle8) {
      $sql = "$copyright
SELECT
   SID			\"SID\",
   UPDATE_COUNT		\"Update count\",
   COMPNAM		\"Component\",
   OBJID		\"Object ID\",
   MSG			\"Message\",
   STEPSOFAR		\"Step sofar\",
   STEPTOTAL		\"Step total\",
   SOFAR		\"Work sofar\",
   TOTALWORK		\"Work total\",
   APPLICATION_DATA_1	\"Data 1\",
   APPLICATION_DATA_2	\"Data 2\",
   APPLICATION_DATA_3	\"Data 3\",
   TO_CHAR(START_TIME,'Month DD, YYYY - HH24:MI')	\"Start time\",
   TO_CHAR(CURRENT_TIME,'Month DD, YYYY - HH24:MI')	\"Current time\"
FROM V\$SESSION_LONGOPS
   WHERE SID = $schema
";
      }

      if ($oracle8i || $oracle9i || $oracle10) {
         $sql = "$copyright
SELECT
   SID			\"SID\",
   OPNAME		\"Operation\",
   TARGET		\"Object\",
   TARGET_DESC		\"Description\",
   SOFAR		\"Work sofar\",
   TOTALWORK            \"Work total\",
   UNITS		\"Units of measure\",
   TO_CHAR(START_TIME,'Month DD, YYYY - HH24:MI')       \"Start time\",
   TO_CHAR(LAST_UPDATE_TIME,'Month DD, YYYY - HH24:MI')	\"Last update time\",
   TO_CHAR(ELAPSED_SECONDS,'999,999,999,999')		\"Elapsed seconds\",
   MESSAGE		\"Message\"
FROM V\$SESSION_LONGOPS
   WHERE SID = $schema
";

      $text = "Long operation information.";
      $link = "";
      $infotext = "No info in V\$SESSION_LONGOPS.";
      DisplayTable($sql,$text,$link,$infotext);
   }

   $sql = "$copyright
SELECT
   NVL(SQL_TEXT,'No SQL available, but cursor is still open.') 						\"SQL text\"
FROM V\$OPEN_CURSOR
   WHERE SADDR = (
SELECT
   SADDR
FROM V\$SESSION WHERE SID= $schema)
";

   $text = "Open cursors.";
   $link = "";
   $infotext = "No open cursors for this session.";
   $count = DisplayTable($sql,$text,$link,$infotext);

   $sql = "$copyright
SELECT
   VALUE
FROM V\$PARAMETER
   WHERE NAME = 'open_cursors'
";
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $open_cursors = $cursor->fetchrow_array;
   $cursor->finish;

   if ($count == $open_cursors) {
      message("Warning: This session has opened the maximum number of cursors allowed by a session ($count). You may need to increase the OPEN_CURSORS parameter. This may also be an indication that your application is not closing cursors properly.");
   }

   $sql = "$copyright
SELECT 
   OBJECT		\"Object name\",
   TYPE			\"Object type\",
   OWNER		\"Owner\"
FROM V\$ACCESS
   WHERE SID= $schema
";

   $text = "Objects being accessed by SID $schema.";
   $infotext = "This SID is not accessing any objects.";
   ObjectTable($sql,$text,$infotext); 

# Show session statistics for a particular SID

   $sql = "$copyright
SELECT 
   A.NAME					\"Parameter name\",
   TO_CHAR(B.VALUE,'999,999,999,999,999')	\"Value\",
   DECODE(A.CLASS,
		1,'User',
		2,'Redo',
		4,'Enqueue',
		8,'Cache',
		16,'OS',
		32,'Parallel server',
		64,'SQL',
		128,'Debug')			\"Class\"
FROM V\$STATNAME A, V\$SESSTAT B
   WHERE A.STATISTIC# = B.STATISTIC#
   AND B.SID = $schema
   AND B.VALUE > 0
ORDER BY 1,3
";
##ORDER BY A.CLASS, A.NAME

   $text = "Session statistics for SID $schema. Only non-zero values displayed.";
   $link = "";
   $infotext = "No current session statistics for SID $schema.";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine showSessionstats");

}

sub showFilegraph {

   logit("Enter subroutine showFilegraph");

   my ($sql,$text,$link,$cursor,$totalreads);
   my ($totalwrites,$file_name,$phyrds,$rdpct,$phywrts,$wrtpct);

   refreshButton();

# Show a graph of datafile activity based on physical writes.

   unless ($oraclei) {

      $sql = "$copyright
SELECT 
   SUM(PHYRDS), SUM(PHYWRTS) 
FROM V\$FILESTAT
";

      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      ($totalreads,$totalwrites) = $cursor->fetchrow_array;
      $cursor->finish;

   } else {

      $sql = "
SELECT * FROM
   (SELECT SUM(PHYRDS) FSREAD FROM V\$FILESTAT),
   (SELECT SUM(PHYRDS) TSREAD FROM V\$TEMPSTAT),
   (SELECT SUM(PHYWRTS) FSWRT FROM V\$FILESTAT),
   (SELECT SUM(PHYWRTS) TSWRT FROM V\$TEMPSTAT) 
";

      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      my ($fsread,$tsread,$fswrt,$tswrt) = $cursor->fetchrow_array;
      $cursor->finish;

      $totalreads = $fsread+$tsread;
      $totalwrites = $fswrt+$tswrt;

   }

   $sql = "$copyright
SELECT 
   NAME							\"File name\",
   TO_CHAR(PHYRDS,'999,999,999,999')			\"Physical reads\",
   TO_CHAR(PHYRDS * 100 / $totalreads,'999')		\"Physical reads %\",
   TO_CHAR(PHYWRTS,'999,999,999,999')			\"Physical writes\",
   TO_CHAR(PHYWRTS * 100 / $totalwrites,'999')		\"Physical writes %\"
FROM V\$DATAFILE DF, V\$FILESTAT FS
   WHERE DF.FILE# = FS.FILE#
ORDER BY PHYWRTS DESC
";

   $sql = "$copyright
SELECT 
   NAME							\"File name\",
   TO_CHAR(PHYRDS,'999,999,999,999')			\"Physical reads\",
   TO_CHAR(PHYRDS * 100 / $totalreads,'999')		\"Physical reads %\",
   TO_CHAR(PHYWRTS,'999,999,999,999')			\"Physical writes\",
   TO_CHAR(PHYWRTS * 100 / $totalwrites,'999')		\"Physical writes %\"
FROM V\$DATAFILE DF, V\$FILESTAT FS
   WHERE DF.FILE# = FS.FILE#
UNION
SELECT 
   NAME							\"File name\",
   TO_CHAR(PHYRDS,'999,999,999,999')			\"Physical reads\",
   TO_CHAR(PHYRDS * 100 / $totalreads,'999')		\"Physical reads %\",
   TO_CHAR(PHYWRTS,'999,999,999,999')			\"Physical writes\",
   TO_CHAR(PHYWRTS * 100 / $totalwrites,'999')		\"Physical writes %\"
FROM V\$TEMPFILE DF, V\$TEMPSTAT FS
   WHERE DF.FILE# = FS.FILE#
ORDER BY 4 DESC
" if ($oraclei);

   logit("SQL: $sql");

   print <<"EOF";
<P>
Datafiles are ordered by physical writes, descending.<P>
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1 ALIGN=CENTER>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>File name</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Reads</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Percentage</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Writes</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Percentage</TH>
EOF
    
   $cursor = $dbh->prepare($sql) or print "$DBI::errstr";
   $cursor->execute;
   while ( ($file_name,$phyrds,$rdpct,$phywrts,$wrtpct) = $cursor->fetchrow_array ) {
      print <<"EOF";
        <TR>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=DATAFILE&arg=$file_name>$file_name</A></TD>
          <TD BGCOLOR='$cellcolor'>
            <TABLE>
              <TR>
                <TD WIDTH=$rdpct BGCOLOR='$linkcolor'><BR></TD>
              </TR>
            </TABLE>
          </TD>
          <TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$rdpct%</TD>
          <TD BGCOLOR='$cellcolor'>
            <TABLE>
              <TR>
                <TD WIDTH=$wrtpct BGCOLOR='$linkcolor'><BR></TD>
              </TR>
            </TABLE>
          </TD>
          <TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$wrtpct%</TD>
        </TR>
EOF
   }
   $cursor->finish;
   print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF

   logit("Exit subroutine showFilegraph");

}

sub showTSfilegraph {

   logit("Enter subroutine showTSfilegraph");

   my $tempfiles_used = $query->param('tempfiles') || "";

   my ($sql,$text,$link,$cursor,$totalreads);
   my ($totalwrites,$file_name,$phyrds,$rdpct,$phywrts,$wrtpct);
   my ($file_id,$bytes,$bytesused,$percent);
   my ($statview,$fileview,$dbaview,$string);

   if ($tempfiles_used) {
      $statview = "V\$TEMPSTAT";
      $fileview = "V\$TEMPFILE";
      $dbaview  = "DBA_TEMP_FILES";
      $string   = "tempfiles";
   } else {
      $statview = "V\$FILESTAT";
      $fileview = "V\$DATAFILE";
      $dbaview  = "DBA_DATA_FILES";
      $string   = "datafiles";
   }
   logit("   Showing stats from $statview,$fileview,$dbaview");

# Show a graph of datafile activity based on physical writes.

   $sql = "$copyright
SELECT
   SUM(PHYRDS), SUM(PHYWRTS)
FROM $statview
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   ($totalreads,$totalwrites) = $cursor->fetchrow_array;
   $cursor->finish;

   $sql = "$copyright
SELECT
   NAME                                                 \"File name\",
   TO_CHAR(PHYRDS,'999,999,999,999')                    \"Physical reads\",
   TO_CHAR(PHYRDS * 100 / $totalreads,'999')            \"Physical reads %\",
   TO_CHAR(PHYWRTS,'999,999,999,999')                   \"Physical writes\",
   TO_CHAR(PHYWRTS * 100 / $totalwrites,'999')          \"Physical writes %\"
FROM $fileview DF, $statview FS
   WHERE DF.FILE# = FS.FILE#
   AND DF.FILE# IN
   (SELECT FILE_ID
FROM $dbaview
WHERE TABLESPACE_NAME = '$schema')
ORDER BY PHYWRTS DESC
";

   logit("SQL: $sql");

   print <<"EOF";
Datafile I/O statistics.<BR>
Entries are ordered by physical writes, descending.<BR>
Percentage shown is in comparison to all other $string in database.<P>
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>File name</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Reads</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Percentage</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Writes</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Percentage</TH>
EOF
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   while ( ($file_name,$phyrds,$rdpct,$phywrts,$wrtpct) = $cursor->fetchrow_array ) {
      print <<"EOF";
        <TR>  
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=DATAFILE&arg=$file_name>$file_name</A></TD>
          <TD BGCOLOR='$cellcolor' WIDTH=100>
            <TABLE>
              <TR>
                <TD WIDTH=$rdpct BGCOLOR='$linkcolor'><BR></TD>
              </TR>
            </TABLE>
          </TD>
          <TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$rdpct%</TD>
          <TD BGCOLOR='$cellcolor' WIDTH=100>
            <TABLE>
              <TR>
                <TD WIDTH=$wrtpct BGCOLOR='$linkcolor'><BR></TD>
              </TR>
            </TABLE>
          </TD>
          <TD BGCOLOR='$cellcolor' ALIGN=RIGHT><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$wrtpct%</TD>
        </TR>
EOF
   }
   $cursor->finish;
   print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF
   
   print "<BR>\n";

   unless ($tempfiles_used) {

# Free space

      $sql = "$copyright
SELECT D.FILE_NAME                                                      \"Filename\",
       D.FILE_ID                                                        \"File ID\",
       TO_CHAR(D.BYTES,'999,999,999,999')                               \"Bytes\",
       TO_CHAR(SUM(E.BYTES),'999,999,999,999')                           \"Bytes used\",
       TO_CHAR(SUM(E.BYTES) / D.BYTES * 100,'999.99')                   \"% used\"
FROM   SYS.DBA_EXTENTS      E,
       SYS.DBA_DATA_FILES   D
WHERE  D.FILE_ID  = E.FILE_ID (+)
AND D.TABLESPACE_NAME = '$schema'
GROUP BY D.FILE_NAME, D.FILE_ID, D.BYTES
";
      print <<"EOF";
Datafile free space.<P>
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>File name</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>File ID</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Bytes</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Bytes used</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Graph</TH>
        <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Percentage full</TH>
EOF

      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      while ( ($file_name,$file_id,$bytes,$bytesused,$percent) = $cursor->fetchrow_array ) {
         print <<"EOF";
        <TR>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=DATAFILE&arg=$file_name>$file_name</A></TD>
          <TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$file_id</TD>
          <TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$bytes</TD>
          <TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$bytesused</TD>
          <TD BGCOLOR='$cellcolor' WIDTH=100>
            <TABLE>
              <TR>
                <TD WIDTH=$percent BGCOLOR='$linkcolor'><BR></TD>
              </TR>
            </TABLE>
          </TD>
          <TD ALIGN=RIGHT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$percent\%</TD>
        </TR>
EOF
      }
      $cursor->finish;
      print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF
   }

   logit("Exit subroutine showTSfilegraph");

}


sub message {

   logit("Enter subroutine message");

# Print a message to the user

   my $message = shift;

   $message = "<FONT COLOR='$infocolor' SIZE='$fontsize' FACE='$font'>$message</FONT>";
   print "<P><B>$message</B></P>\n";

   logit("Exit subroutine message");

}

sub text {

   logit("Enter subroutine text");

# Print a message to the user

   my $message = shift;

   $message = "<FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$message</FONT>";
   print "<P><B>$message</B></P>\n";

   logit("Exit subroutine text");

}

sub commify {

   logit("Enter subroutine commify");

# Puts commas in a numeral

   my $text = reverse $_[0];
   $text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
   return scalar reverse $text;

   logit("Exit subroutine commify");

}

sub dbfileBlock {

   logit("Enter subroutine dbfileBlock");

   my ($sql,$text,$infotext,$link);

   $sql = "$copyright
SELECT 
   SEGMENT_NAME,
   SEGMENT_TYPE,
   OWNER
FROM DBA_EXTENTS
   WHERE FILE_ID = (
SELECT FILE#
   FROM V\$DATAFILE
WHERE NAME = '$object_name')
   AND $whereclause BETWEEN
      BLOCK_ID AND BLOCK_ID + BLOCKS - 1
";

   $text = "Object occupying block $whereclause of file $object_name";
   $link = "";
   $infotext = "No object found";
   ObjectTable($sql,$text,$infotext);

   logit("Exit subroutine dbfileBlock");

}

sub statsPackAdmin {

   logit("Enter subroutine statsPackAdmin");

   my ($sql,$command);

   $command = $query->param('command');

   logit("   Command is $command");

   if ($command eq "snapshot") {

      logit("   Enter sub-subroutine snapshot");

# Take a statsPack snapshot.

      message("Taking Statspack snapshot...");

      $sql = "
BEGIN
   $statspack_schema.STATSPACK.SNAP;
END;
";

      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      $cursor->finish;

      message("Statspack snapshot complete.");

      Button("$scriptname?database=$database&object_type=STATSPACKADMIN&command=statsgroups TARGET=body","Snapshot analyzation / admin","$headingcolor","CENTER","200");

      logit("   Exit sub-subroutine snapshot");
   }

   if ($command eq "statsgroups") {

      logit("   Enter sub-subroutine statsgroups");

# Show groups of statistics between each database startup / shutdown.

      my ($start_snap_id,$end_snap_id,$startup_time,$numsnaps,$start_snap_time,$end_snap_time);

      text("Choose one or more groups of statistics to analyze and / or delete.<BR>Or choose range to select a subset of snapshots.");

      $sql = "
SELECT
   MIN(SNAP_ID),
   MAX(SNAP_ID),
   TO_CHAR(STARTUP_TIME,'Mon DD YYYY @ HH24:MI:SS'),
   TO_CHAR(COUNT(*),'999,999,999,999'),
   TO_CHAR(MIN(SNAP_TIME),'Mon DD YYYY @ HH24:MI:SS'),
   TO_CHAR(MAX(SNAP_TIME),'Mon DD YYYY @ HH24:MI:SS')
FROM $statspack_schema.STATS\$SNAPSHOT
   WHERE INSTANCE_NUMBER = (
SELECT INSTANCE_NUMBER
   FROM V\$INSTANCE
)
   GROUP BY STARTUP_TIME
   ORDER BY STARTUP_TIME
";

      print <<"EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <FORM METHOD=POST ACTION=$scriptname>
    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
    <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Execute">
    <P>
    <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
    <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
    <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="STATSPACKADMIN">
    <INPUT TYPE="HIDDEN" NAME="command" VALUE="snapadmin">
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Analyze</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Delete</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Range</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Startup time</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'># Snapshots</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>First snap / Snap ID</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Last snap / Snap ID</TH>
EOF

      $cursor = $dbh->prepare($sql);
      $cursor->execute;

      while (($start_snap_id,$end_snap_id,$startup_time,$numsnaps,$start_snap_time,$end_snap_time) = $cursor->fetchrow_array) {
         print <<"EOF";
        <TR>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><INPUT TYPE=CHECKBOX NAME=analyze~$start_snap_id~$end_snap_id></TD>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><INPUT TYPE=CHECKBOX NAME=delete~$start_snap_id~$end_snap_id></TD>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><INPUT TYPE=CHECKBOX NAME=range~$start_snap_id~$end_snap_id></TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$startup_time</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$numsnaps</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$start_snap_time ($start_snap_id)</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$end_snap_time ($end_snap_id)</TD>
        </TR>
EOF
      }
      $cursor->finish;

      print <<"EOF";
      </TABLE>
    </TD>
  </TR>
  </FORM>
</TABLE>
EOF
      logit("   Exit sub-subroutine statsgroups");
   }

   if ($command eq "snapadmin") {

      logit("   Enter sub-subroutine snapadmin");

# Analyze and / or delete snapshots.

      my (@params,$param,$start_snap_id,$end_snap_id);
      my ($snap_id,$snap_time);
      $start_snap_id = 0;
      $end_snap_id = 0;
      @params = $query->param;
      foreach $param(@params) {
         if ($param =~ /^analyze~/) {
            logit("      Enter sub-sub-subroutine analyze");
            $param =~ s/analyze~//;
            ($start_snap_id,$end_snap_id) = split("~", $param);
            logit("      Analyzing all snapshots from $start_snap_id to $end_snap_id"); 
            logit("      Exit sub-sub-subroutine analyze");
            statsPackSnapAnalyze($start_snap_id,$end_snap_id);
         }
         if ($param =~ /^delete~/) {
            logit("      Enter sub-sub-subroutine delete");
            $param =~ s/delete~//;
            ($start_snap_id,$end_snap_id) = split("~", $param);
            logit("      Deleting all snapshots from $start_snap_id to $end_snap_id"); 
            logit("      Exit sub-sub-subroutine delete");
            statsPackSnapDelete($start_snap_id,$end_snap_id);
         }
         if ($param =~ /^rangeanalyze~/) {
            logit("      Enter sub-sub-subroutine rangeanalyze");
            $param =~ s/rangeanalyze~//;  
            $snap_id = $param;
            logit("         Snap ID received is $snap_id"); 
            $end_snap_id = $snap_id if $start_snap_id;
            $start_snap_id = $snap_id unless $start_snap_id;
            if ($start_snap_id && $end_snap_id) {
               logit("      Analyzing all snapshots from $start_snap_id to $end_snap_id"); 
               logit("      Exit sub-sub-subroutine rangeanalyze");
               statsPackSnapAnalyze($start_snap_id,$end_snap_id);
               exit;
            }
         }
         if ($param =~ /^range~/) {
            logit("      Enter sub-sub-subroutine range");
            $param =~ s/range~//;
            ($start_snap_id,$end_snap_id) = split("~", $param);
            logit("      Displaying a range menu for all snapshots from $start_snap_id to $end_snap_id");

            text("Check two boxes only, indicating the start snapshot and the end snapshot that you would like to analyze.");

            print <<"EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <FORM METHOD=POST ACTION=$scriptname>
    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
    <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Analyze by range">
    <P>
    <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
    <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="STATSPACKADMIN">
    <INPUT TYPE="HIDDEN" NAME="command" VALUE="snapadmin">
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Mark</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Snap ID</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Snapshot date</TH>
EOF

            $sql = "$copyright
SELECT
   SNAP_ID,
   TO_CHAR(SNAP_TIME,'Mon DD YYYY @ HH24:MI:SS')
FROM STATS\$SNAPSHOT
   WHERE INSTANCE_NUMBER = (
SELECT INSTANCE_NUMBER
   FROM V\$INSTANCE
)
   AND SNAP_ID BETWEEN $start_snap_id AND $end_snap_id
";

            $cursor = $dbh->prepare($sql);
            $cursor->execute;
            while (($snap_id,$snap_time) = $cursor->fetchrow_array) {
               print <<"EOF";
        <TR>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><INPUT TYPE=CHECKBOX NAME=rangeanalyze~$snap_id></TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$snap_id</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$snap_time</TD>
        </TR>
EOF
            }
            $cursor->finish;
            print <<"EOF";
      </TABLE>
    </TD>
  </TR>
  </FORM>
</TABLE>
EOF
            logit("      Exit sub-sub-subroutine range");
         }
      }   
      logit("   Exit sub-subroutine snapadmin");
   }

   logit("Exit subroutine statsPackAdmin");

}

sub statsPackSnapDelete {

   logit("Enter subroutine statsPackSnapDelete");

      my $start_snap_id    = shift;
      my $end_snap_id      = shift;
      my ($sql,$cursor,$instance_number,$rows_deleted);
      my ($startup_time,$numsnaps,$start_snap_time,$end_snap_time);

# Get the instance number we are attached to. All queries
# should be based on instance number, due to OPS.

   $sql = "
SELECT
   INSTANCE_NUMBER
FROM V\$INSTANCE
";
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $instance_number = $cursor->fetchrow_array;
   $cursor->finish;

# Get some values for informational purposes.

   $sql = "
SELECT
   TO_CHAR(STARTUP_TIME,'Mon DD YYYY @ HH24:MI:SS'),
   TO_CHAR(COUNT(*),'999,999,999,999'),
   TO_CHAR(MIN(SNAP_TIME),'Mon DD YYYY @ HH24:MI:SS'),
   TO_CHAR(MAX(SNAP_TIME),'Mon DD YYYY @ HH24:MI:SS')
FROM $statspack_schema.STATS\$SNAPSHOT
   WHERE INSTANCE_NUMBER = $instance_number
   AND SNAP_ID BETWEEN $start_snap_id and $end_snap_id
GROUP BY STARTUP_TIME
ORDER BY STARTUP_TIME
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   ($startup_time,$numsnaps,$start_snap_time,$end_snap_time) = $cursor->fetchrow_array;
   $cursor->finish;

   text("Deleting snapshot analyzation for period spanning $start_snap_time to $end_snap_time ($numsnaps snapshots)<BR>Database: $database - Instance#: $instance_number");

   $sql = "
DELETE
   FROM $statspack_schema.STATS\$SNAPSHOT
WHERE INSTANCE_NUMBER = $instance_number
AND SNAP_ID BETWEEN $start_snap_id and $end_snap_id
";
   $rows_deleted = $dbh->do($sql);

   message("Delete complete. $rows_deleted rows affected.");

   logit("Exit subroutine statsPackSnapDelete");

}

sub statsPackSnapAnalyze {

   logit("Enter subroutine statsPackSnapAnalyze");

   my $start_snap_id	= shift;
   my $end_snap_id	= shift;
   my ($sql,$cursor,$startup_time,$instance_number,$text,$link,$infotext);
   my ($numsnaps,$start_snap_time,$end_snap_time);

# Get the instance number we are attached to. All queries
# should be based on instance number, due to OPS.

   $sql = "
SELECT
   INSTANCE_NUMBER
FROM V\$INSTANCE
";
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $instance_number = $cursor->fetchrow_array;
   $cursor->finish;

# Check to make sure we are not spanning startup / shutdown
# with the range of snap_id's submitted. Blow up if we are.
# This should not be neccesary when being called from snapAdmin.

#   $sql = "
#SELECT COUNT(DISTINCT STARTUP_TIME)
#   FROM STATS\$SNAPSHOT
#WHERE INSTANCE_NUMBER = $instance_number
#AND SNAP_ID BETWEEN $start_snap_id and $end_snap_id
#";

#   if (recordCount($dbh,$sql) > 1) {
#      ErrorPage("You have specified a range that spans database startups. That is invalid.");
#   }

# Get some values for informational purposes.

   $sql = "
SELECT
   TO_CHAR(STARTUP_TIME,'Mon DD YYYY @ HH24:MI:SS'),
   TO_CHAR(COUNT(*),'999,999,999,999'),
   TO_CHAR(MIN(SNAP_TIME),'Mon DD YYYY @ HH24:MI:SS'),
   TO_CHAR(MAX(SNAP_TIME),'Mon DD YYYY @ HH24:MI:SS')
FROM $statspack_schema.STATS\$SNAPSHOT
   WHERE INSTANCE_NUMBER = $instance_number
   AND SNAP_ID BETWEEN $start_snap_id and $end_snap_id
GROUP BY STARTUP_TIME
ORDER BY STARTUP_TIME
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   ($startup_time,$numsnaps,$start_snap_time,$end_snap_time) = $cursor->fetchrow_array;
   $cursor->finish;

   text("Database: $database - Instance#: $instance_number<P>Snapshot analyzation for period spanning <BR>$start_snap_time (Snap ID $start_snap_id) to $end_snap_time (Snap ID $end_snap_id) <BR>($numsnaps snapshots)");

# Tablespace I/O information.

   $sql = "
SELECT
   A.TSNAME						\"Tablespace name\",
   TO_CHAR(B.PHYRDS-A.PHYRDS,'999,999,999,999')		\"Phy. reads\",
   TO_CHAR(B.PHYWRTS-A.PHYWRTS,'999,999,999,999')	\"Phy. writes\"
FROM 
   (SELECT
      TSNAME,
      SUM(PHYRDS)	PHYRDS,
      SUM(PHYWRTS)	PHYWRTS 
      FROM $statspack_schema.STATS\$FILESTATXS
   WHERE INSTANCE_NUMBER = $instance_number
   AND SNAP_ID = $start_snap_id
   GROUP BY TSNAME) A,
   (SELECT
      TSNAME,
      SUM(PHYRDS)	PHYRDS,
      SUM(PHYWRTS)	PHYWRTS
   FROM $statspack_schema.STATS\$FILESTATXS
   WHERE INSTANCE_NUMBER = $instance_number
   AND SNAP_ID = $end_snap_id
   GROUP BY TSNAME) B
WHERE A.TSNAME = B.TSNAME
ORDER BY 3 DESC , 2 DESC
";

      $text = "Tablespace I/O statistics.";
      $link = "$scriptname?database=$database&object_type=TSINFO";
      $infotext = "No tablespace I/O statistics found.";
      DisplayTable($sql,$text,$link,$infotext);

# Datafile I/O information.

   $sql = "
SELECT 
   A.FILENAME						\"Filename\",
   TO_CHAR(B.PHYRDS-A.PHYRDS,'999,999,999,999')		\"Phy. reads\",
   TO_CHAR(B.PHYWRTS-A.PHYWRTS,'999,999,999,999')	\"Phy. writes\"
FROM 
   (SELECT
      FILENAME,
      PHYRDS,
      PHYWRTS 
      FROM $statspack_schema.STATS\$FILESTATXS
   WHERE INSTANCE_NUMBER = $instance_number
   AND SNAP_ID = $start_snap_id) A,
   (SELECT
      FILENAME,
      PHYRDS,
      PHYWRTS
   FROM $statspack_schema.STATS\$FILESTATXS
   WHERE INSTANCE_NUMBER = $instance_number
   AND SNAP_ID = $end_snap_id) B
WHERE A.FILENAME = B.FILENAME
ORDER BY 3 DESC , 2 DESC
";

      $text = "Datafile I/O statistics.";
      $link = "$scriptname?database=$database&object_type=DATAFILE";
      $infotext = "No datafile statistics found.";
      DisplayTable($sql,$text,$link,$infotext);

# Rollback segment information

   $sql = "
SELECT
   C.SEGMENT_NAME						\"Segment name\",
   TO_CHAR(E.GETS - B.GETS,'999,999,999,999')			\"Gets\",
   TO_CHAR(TO_NUMBER(DECODE(E.GETS ,B.GETS, NULL,
      (E.WAITS  - B.WAITS) * 100/(E.GETS - B.GETS))),'999.99')	\"Waits %\",
   TO_CHAR(E.WRITES - B.WRITES,'999,999,999,999')		\"Writes\",
   TO_CHAR(E.WRAPS - B.WRAPS,'999,999,999,999')			\"Wraps\",
   TO_CHAR(E.SHRINKS - B.SHRINKS,'999,999,999,999')		\"Shrinks\",
   TO_CHAR(E.EXTENDS - B.EXTENDS,'999,999,999,999')		\"Extends\"
FROM 
   $statspack_schema.STATS\$ROLLSTAT B,
   DBA_ROLLBACK_SEGS C,
   $statspack_schema.STATS\$ROLLSTAT E
WHERE B.SNAP_ID         = $start_snap_id
   AND E.SNAP_ID         = $end_snap_id
   AND B.INSTANCE_NUMBER = $instance_number
   AND E.INSTANCE_NUMBER = $instance_number
   AND B.INSTANCE_NUMBER = E.INSTANCE_NUMBER
   AND E.USN             = B.USN
   AND C.SEGMENT_ID      = B.USN
ORDER BY E.USN
";

      $text = "Rollback segment statistics.";
      $link = "$scriptname?database=$database&object_type=ROLLBACK";
      $infotext = "No rollback statistics found.";
      DisplayTable($sql,$text,$link,$infotext);

}

sub objectFragMap {

   logit("Enter subroutine objectFragMap");

   my ($sql1,$sql2,$cursor1,$cursor2,$file_name,$file_id,$bytes,$blocks);
   my ($block_id,$block_count,@block_ids,@block_counts,$counter,$extent_count);
   my ($collength,$colcounter,$arraycounter,$blockstart,$blockfinish,$i);
   my ($extentcolor,$foo,$partitioned,$iot_type);

   if ($oracle8) {
      $sql1 = "$copyright
SELECT
   PARTITIONED,
   IOT_TYPE
FROM DBA_TABLES
   WHERE OWNER = '$schema'
   AND TABLE_NAME = '$object_name'
";
      $cursor1 = $dbh->prepare($sql1);
      $cursor1->execute;
      ($partitioned,$iot_type) = $cursor1->fetchrow_array;
      $cursor1->finish;

      if ($partitioned eq "YES") {
         message("Extent mapping for partitioned tables is not yet supported.");
         exit;
      }
      if ($iot_type eq "IOT") {
         message("Extent mapping for Index Organized Tables is not yet supported.");
         exit;
      }
   }

   if (checkPriv("EXECUTE ANY PROCEDURE") && checkPriv("ANALYZE ANY")) {

      logit("   Executing DBMS_SPACE.UNUSED_SPACE");

      $sql = "$copyright
BEGIN
   SYS.DBMS_SPACE.UNUSED_SPACE(?,?,?,?,?,?,?,?,?,?);
END;
";

      my ($total_blocks,$total_bytes,$unused_blocks,$unused_bytes,$last_used_extent_file_id);
      my ($last_used_extent_block_id,$last_used_block,$usedpct,$unusedpct,$text,$link,$used_blocks);

      $cursor = $dbh->prepare($sql);
      $cursor->bind_param(1,"$schema");
      $cursor->bind_param(2,"$object_name");
      $cursor->bind_param(3,"TABLE");
      $cursor->bind_param_inout(4, \$total_blocks,80);
      $cursor->bind_param_inout(5, \$total_bytes,80);
      $cursor->bind_param_inout(6, \$unused_blocks,80);
      $cursor->bind_param_inout(7, \$unused_bytes,80);
      $cursor->bind_param_inout(8, \$last_used_extent_file_id,80);
      $cursor->bind_param_inout(9, \$last_used_extent_block_id,80);
      $cursor->bind_param_inout(10,\$last_used_block,80);
      $cursor->execute;
      $cursor->finish;
      logit("   Stored procedure returned :\nTotal blocks: $total_blocks\nTotal bytes: $total_bytes\nUnused blocks: $unused_blocks\nUnused bytes: $unused_bytes\nLast used extent file id: $last_used_extent_file_id\nlast used extent block ID: $last_used_extent_block_id");

      $sql = "$copyright
SELECT
   TO_CHAR($total_blocks,'999,999,999,999')			\"Total blocks\",
   TO_CHAR($total_bytes,'999,999,999,999')			\"Total bytes\",
   TO_CHAR($unused_blocks,'999,999,999,999')			\"Unused blocks\",
   TO_CHAR($unused_bytes,'999,999,999,999')			\"Unused bytes\",
   TO_CHAR($last_used_extent_file_id,'999,999,999,999')		\"Last used extent file ID\",
   TO_CHAR($last_used_extent_block_id,'999,999,999,999')	\"Last used extent block_id\"
FROM DUAL
";
      $text = "Real-time space usage via DBMS_SPACE.";
      $link = "";
      DisplayTable($sql,$text,$link);

      $used_blocks = $total_blocks-$unused_blocks;
      $usedpct = int(($used_blocks/$total_blocks)*100);
      $unusedpct = 100-$usedpct;
      $unused_blocks = commify($unused_blocks);
      $unused_bytes = commify($unused_bytes);
      text("$usedpct\% of the allocated space for this table is being used. There are $unused_blocks blocks above the highwater mark, totaling $unused_bytes bytes which are allocated, but have never been used since table creation or the last truncate.") unless $DBI::errstr;
   }

   text("</CENTER>Extent mapping for object $schema.$object_name. This may be a long running query for large objects with many extents, or for very large databases.");

# Get a list of files that this object spans.

   $sql1 = "$copyright
SELECT 
   FILE_NAME,
   FILE_ID,
   TO_CHAR(BYTES,'999,999,999,999'),
   BLOCKS
FROM DBA_DATA_FILES
   WHERE FILE_ID IN (
SELECT DISTINCT
   FILE_ID
FROM DBA_EXTENTS
   WHERE SEGMENT_NAME = '$object_name'
   AND OWNER = '$schema'
)
   ORDER BY FILE_ID
";
   $cursor1=$dbh->prepare($sql1) or ErrorPage("$DBI::errstr");
   $cursor1->execute;

   text("Extents are shown in alternating white / blue so that they can be distinguished from each other. Blocks shown in green are either free or allocated by other objects.");

# Loop through the datafiles.

   while (($file_name,$file_id,$bytes,$blocks) = $cursor1->fetchrow_array) {
      
      logit("   Working on file $file_name for object $schema.$object_name");
      undef @block_ids;
      undef @block_counts;

      $sql2 = "$copyright
SELECT BLOCK_ID, BLOCKS
   FROM DBA_EXTENTS
WHERE FILE_ID = '$file_id'
   AND SEGMENT_NAME = '$object_name'
   AND OWNER = '$schema'
   ORDER BY BLOCK_ID
";
      $cursor2=$dbh->prepare($sql2);
      $cursor2->execute;
      while (($block_id, $block_count) = $cursor2->fetchrow_array) {
         push @block_ids, $block_id;
         push @block_counts, $block_count;
      }
      $cursor2->finish;

      $extent_count	= $#block_ids+1;
      logit("   Extent count is $extent_count");

# This is for serious debugging only. Major output for objects with
# many extents.
#      for ($counter = 0; $counter <= $#block_ids; $counter++) {
#         logit("   Segment: $object_name Owner: $schema");
#         logit("   Block_id: $block_ids[$counter] Count: $block_counts[$counter]");
#      }

# Create the image

      $collength	= 150;
      $colcounter	= 0;
      $arraycounter	= 0;

      text("</CENTER>Extent map for $schema.$object_name, datafile $file_name<BR>File is $bytes bytes ($blocks blocks of $db_block_size bytes)<BR>$schema.$object_name has $extent_count extent(s) in this datafile");

      print "<FONT SIZE=1><B></CENTER>\n";
      print "<FONT COLOR=GREEN>";
      $blockstart	= $block_ids[$arraycounter];
      $blockfinish	= $blockstart+$block_counts[$arraycounter]-1;
      logit("   Block start = $blockstart: Block finish = $blockfinish");
# Go from 0 to the number of blocks in the datafile
      for ($i = 1; $i < $blocks; $i++) {
# If $i is equal to the start block_id of the extent, turn the font blue.
         if ($i == $blockstart) {
            if ($foo) {
               $extentcolor = "BLUE";
               $foo--;
            } else {
               $extentcolor = "WHITE";
               $foo++
            }
            print "<FONT COLOR=$extentcolor>";
#            logit("   i reached blockstart $blockstart: i = $i");
         }
         print "I";
         if ($i == $blockfinish) {
            print "<FONT COLOR=GREEN>";
#            logit("   i reached blockfinish $blockfinish: i = $i");
            $arraycounter++;
            if ($arraycounter > $#block_ids) {
               logit("   End of array reached at element $arraycounter.");
               $blockstart = $blocks+1;
               $blockfinish      = $blockstart+$block_counts[$arraycounter];
            } else {
               $blockstart       = $block_ids[$arraycounter];
               $blockfinish      = $blockstart+$block_counts[$arraycounter]-1;
            }
         }
         $colcounter++;
         if ($colcounter == $collength) {
           print "<BR>\n";
           $colcounter = 0;
         }
      }
   }
   print "</FONT><CENTER></B>";
   print "<FONT FACE=\"$font\" SIZE=\"$fontsize\" COLOR=\"$fontcolor\">\n";
   $cursor1->finish;

   logit("Exit subroutine objectFragMap");

}

sub fragList {

   logit("Enter subroutine fragList");

# Prints a list of used and free fragments.

   my ($sql,$text,$link);

   $sql = "
SELECT
   BLOCK_ID					\"Begin block ID\",
   FILE_NAME					\"Filename\",
   SEGMENT_NAME					\"Segment name\",
   BYTES					\"Bytes used\",
   BLOCKS					\"Blocks used\"
FROM
(
SELECT
   TO_CHAR(DFS.BLOCK_ID,'999,999,999,999')	\"BLOCK_ID\",
   TO_CHAR(DFS.BYTES,'999,999,999,999')		\"BYTES\",
   TO_CHAR(DFS.BLOCKS,'999,999,999,999')	\"BLOCKS\",
   DFS.FILE_ID					\"FILE_ID\",
   'Unused'					SEGMENT_NAME,
   DDF.FILE_NAME				\"FILE_NAME\"
FROM DBA_FREE_SPACE DFS, DBA_DATA_FILES DDF
   WHERE DFS.TABLESPACE_NAME = '$object_name'
   AND DFS.FILE_ID = DDF.FILE_ID
UNION
SELECT
   TO_CHAR(DE.BLOCK_ID,'999,999,999,999'),
   TO_CHAR(DE.BYTES,'999,999,999,999'),
   TO_CHAR(DE.BLOCKS,'999,999,999,999'),
   DE.FILE_ID,
   DE.SEGMENT_NAME,
   DDF.FILE_NAME
FROM DBA_EXTENTS DE, DBA_DATA_FILES DDF
   WHERE DE.TABLESPACE_NAME = '$object_name'
   AND DE.FILE_ID = DDF.FILE_ID
) A
   ORDER BY A.FILE_ID, A.BLOCK_ID
";

   $text = "Extent listing for tablespace $object_name";
   $link = "";
   DisplayTable($sql,$text,$link);

   logit("Exit subroutine fragList");

}

sub fragMap {

   logit("Enter subroutine fragMap");

# Creates a datafile fragmentation map, 
# showing used and unused blocks.

   my ($sql,$sql1,$cursor,$cursor1,$file_id,$blocks);
   my ($collength,$width,$height,$hstart,$vstart);
   my ($blockused,$blockfree,$x,$y,$numblocks);
   my ($colcounter,$image,$id,$i,$pointer,$length);
   my ($block_id,$counter,$file_name,$bytes);
   my (@datafiles);

   if ($whereclause eq "datafile") {
      push @datafiles, $object_name;
   }

   if ($whereclause eq "tablespace") {
      $sql = "$copyright
SELECT
   FILE_NAME
FROM DBA_DATA_FILES
   WHERE TABLESPACE_NAME = '$object_name'
ORDER BY FILE_NAME
";

      $cursor=$dbh->prepare($sql);
      $cursor->execute;
      while ($file_name = $cursor->fetchrow_array) {
         push @datafiles, $file_name;
      }
      $cursor->finish;
   }

# Loop through the datafiles.

   foreach $file_name(@datafiles) {

      $sql = "$copyright
SELECT 
   FILE_ID, 
   TO_CHAR(BYTES,'999,999,999,999'), 
   BLOCKS
FROM DBA_DATA_FILES 
   WHERE FILE_NAME = '$file_name'
";

      $cursor=$dbh->prepare($sql);
      $cursor->execute;
      while (($file_id,$bytes,$blocks) = $cursor->fetchrow_array) {
      
         $sql1 = "$copyright
SELECT BLOCK_ID, BLOCKS
   FROM DBA_EXTENTS
WHERE FILE_ID = '$file_id'
   ORDER BY BLOCK_ID
";
         $cursor1=$dbh->prepare($sql1);
         $cursor1->execute;
      
# Create the image

         $collength = 150;
         $colcounter = 1;
         $counter = 1;
         $pointer = 1;
         $hstart = 0;
         $x = 0;

         text("</CENTER>Fragmentation map for datafile $file_name<BR>File is $bytes bytes ($blocks blocks of $db_block_size bytes)");

         print "<FONT SIZE=1><B></CENTER>\n";
         while (($block_id,$numblocks) = $cursor1->fetchrow) {
            print "<FONT COLOR=GREEN>";
            for ($i = $pointer; $i < $block_id; $i++) {
               print "I";
               $x = $x+1;
               if ($x == $collength) {
                 print "<BR>\n";
                 $x = $hstart;
                 $colcounter=0;
               }
               $pointer++;
            }
            print "<FONT COLOR=RED>";
            for ($i = 1; $i <= $numblocks; $i++ ) {
               print "I";
               $x = $x+1;
               if ($x == $collength+$hstart) {
                 print "<BR>\n";
                 $x = $hstart;
                 $colcounter=0;
               }
               $counter = $block_id + $numblocks + 1;
               $pointer++;
            }
         }
         $cursor1->finish;
         print "<FONT COLOR=GREEN>";
         for ($i = $pointer; $i <= $blocks; $i++) {
            print "I";
            $x = $x+1;
            if ($x == $collength+$hstart) {
               print "<BR>\n";
               $x = $hstart;
               $colcounter=0;
            }
            $pointer++;
         }
      }
      $cursor->finish;
   print "</FONT><CENTER></B>";
   print "<FONT FACE=\"$font\" SIZE=\"$fontsize\" COLOR=\"$fontcolor\">\n";
   }

   logit("Exit subroutine fragMap");

}

sub about {

   logit("Enter subroutine about");

# Give me a pat on the back. :)

   my ($title,$heading,$fontsize,$encstring,$text);
   my ($sessionid,$mydatabase,$myusername,$mypassword);

   $title	= "Oracletool v$VERSION";
   $heading	= "</CENTER><B>Thanks for using Oracletool!</B><BR>";

   if ($encryption_enabled) {
      $encstring = "Cookie encryption is enabled, level $encryption_enabled of 2.";
    } else {
      $encstring = "Cookie encryption is not enabled.";
   }
   
   # Check to see if MyOracletool username and connection string
   # are set. If so, display them as well FYI.

   $sessionid = cookie("MyOracletool");
   $mydatabase = cookie("MyOracletoolDB");

   if ($sessionid && $mydatabase) {
      ($myusername,$mypassword) = decodeSessionid($sessionid);
   }

   if ($mydatabase && $myusername) {
      $text = "<P>Your Oracletool repository is $myusername\@$mydatabase";
   } else {
      $text = "";
   }

   Header($title,$heading,$font,$fontsize,$fontcolor,$bgcolor);
print <<"EOF";
<BR>
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TR>
          <TD BGCOLOR='$cellcolor'>
            <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
            oracletool.pl version $VERSION<BR>
            <HR ALIGN=LEFT WIDTH=75% NOSHADE SIZE=1>
            $encstring<BR>
            Your theme is set to $theme.
            $text
          </TD>
        </TR>
      </TABLE>
    </TD>
  </TR>
</TABLE>
<BR>
Written and maintained by Adam vonNieda in Kansas, USA.<P>
Copyright 1998 - 2010 Adam vonNieda<BR>
You may distribute under the terms of either the GNU General Public<BR>
License or the Artistic License, as specified in the Perl README file,<BR>
with the exception that it cannot be placed on a CD-ROM or similar media<BR>
for commercial distribution without the prior approval of the author.<P>
Home site: <A HREF="http://www.oracletool.com">http://www.oracletool.com</A><BR><BR>
Questions, comments, bug reports, and suggestions are encouraged!<BR>
Tell me what to do to make it better!<BR>
Drop me a note at <A HREF="mailto:adam\@oracletool.com">adam\@oracletool.com</A>.<BR><BR>
I'd like to thank everyone (too many to name) who has contributed to this<BR>
project be it through suggestions, criticism, or code contributions.<BR>
Oracletool is a useful product because of you! 
EOF

   logit("Exit subroutine about");

   exit;
}

sub advrep {

   logit("Enter subroutine advrep");

# Find out if this server is an advanced replication
# master server.

   my ($sql,$cursor,$count);

   $count = 0;

   $sql = "$copyright
SELECT
   COUNT(*)
FROM DBA_REPGROUP
";

   $cursor=$dbh->prepare($sql);
   if ($cursor) {
      $cursor->execute;
      $count=$cursor->fetchrow;
      $cursor->finish;
      return($count);
   } else {
      return(0);
   }

   logit("Exit subroutine advrep");

}

sub repmaster {

   logit("Enter subroutine repmaster");

# Find out if this server is the master for
# replication.

   my ($sql,$cursor,$count);

   $sql = "$copyright
SELECT 
   COUNT(*) 
FROM DBA_REGISTERED_SNAPSHOTS
";

   $cursor=$dbh->prepare($sql);
   $cursor->execute;
   $count=$cursor->fetchrow;
   $cursor->finish;
   return $count;

   logit("Exit subroutine repmaster");

}

sub repsnapshot {

   logit("Enter subroutine repsnapshot");

# Find out if this instance has snapshots
# replicated from a master.

   my ($sql,$cursor,$count);

   $sql = "$copyright
SELECT 
   COUNT(*) 
FROM DBA_SNAPSHOTS
";

   $cursor=$dbh->prepare($sql);
   $cursor->execute;
   $count=$cursor->fetchrow;
   $cursor->finish;
   return $count;

   logit("Exit subroutine repsnapshot");

}

sub rmanCatalogExists {

   logit("Enter subroutine rmanCatalogExists");

# Find out if there is one or more Recovery Manager
# catalogs in this database. This pertains to 
# Oracle8 and above only.

   my ($sql,$cursor,$count);

   $sql = "$copyright
SELECT
   COUNT(*)
FROM DBA_TABLES
   WHERE TABLE_NAME = 'RCVER'
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $count = $cursor->fetchrow_array;
   $cursor->finish;
   return($count); 

   logit("Exit subroutine rmanCatalogExists");
}

sub backupsFound {

   logit("Enter subroutine backupsFound");

   my ($sql,$cursor,$count);

   $sql = "$copyright
SELECT
   COUNT(*)
FROM V\$BACKUP_DATAFILE
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   $count = $cursor->fetchrow_array;
   $cursor->finish;
   return($count); 

   logit("Exit subroutine backupsFound");

}

sub parallel {

   logit("Enter subroutine parallel");

# Find out if this is a parallel database.
# Oracle8 only. I'm not going to cover Oracle7
# parallel databases at this time.

   if (! $oracle7) {
      my $sql = "$copyright
SELECT VALUE
   FROM V\$PARAMETER
WHERE NAME = 'parallel_server'
";

      my $cursor = $dbh->prepare($sql);
      $cursor->execute;
      my $foo = $cursor->fetchrow_array;
      $cursor->finish;
      if ( $foo eq "TRUE" ) {
         return 1; 
       } else {
         return 0; 
      }
    } else {
   return 0;
   }

   logit("Exit subroutine parallel");

}

sub DisplayGraph {

   logit("Enter subroutine DisplayGraph");

   my $graphtype	= shift;
   my $object_name	= shift;
   my $text		= shift;

   my ($file,$tablespace_name,$rgif,$vgif,$sql,$cursor);

   if ($graphtype eq "dbfile") {
      $sql = "$copyright
SELECT TABLESPACE_NAME 
   FROM DBA_DATA_FILES
WHERE FILE_NAME = '$object_name'
";
      $cursor=$dbh->prepare($sql);
      $cursor->execute;
      $tablespace_name = $cursor->fetchrow_array;
      $cursor->finish;
      $file = basename($object_name);
      $rgif = "$ENV{DOCUMENT_ROOT}/$repository/$database/$tablespace_name/$file.gif";
      $vgif = "$repository/$database/$tablespace_name/$file.gif";
   }

   if ($graphtype eq "sessions") {
      $rgif = "$ENV{DOCUMENT_ROOT}/$repository/$database/sessions.gif";
      $vgif = "$repository/$database/sessions.gif";
   }

# If the image file does not exist, return.
   if (! -e $rgif) {
      return (1);
   }

   print <<"EOF" if defined ($text);
<P><B>$text</B>
EOF
print "<IMG SRC=$vgif>\n";

   logit("Exit subroutine DisplayGraph");

}

sub showGrantButton {

   logit("Enter subroutine showGrantButton");

   my ($sql,$cursor,$count);

   $sql = "$copyright
SELECT COUNT(*)
   FROM DBA_TAB_PRIVS
WHERE TABLE_NAME = '$object_name'
AND OWNER = '$schema'
";

   $cursor=$dbh->prepare($sql);
   $cursor->execute;
   $count = $cursor->fetchrow_array;
   $cursor->finish;

   if ($count > 0 ) {

   print <<"EOF";
<BR>
<TABLE BORDER=0 CELLPADDING=0 CELLSPACING=0>
  <TR>
    <TD ALIGN=CENTER>
      <FORM METHOD="GET" ACTION="$scriptname">
        <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
        <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
        <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="OBJECTGRANTS">
        <INPUT TYPE="HIDDEN" NAME="schema" VALUE="$schema">
        <INPUT TYPE="HIDDEN" NAME="arg" VALUE="$object_name">
        <INPUT TYPE="SUBMIT" NAME="tablerows" VALUE="Display ($count) grants">
      </FORM>
    </TD>
  </TR>
</TABLE>
EOF
   }

   logit("Exit subroutine showGrantButton");

   return($count);
}

sub showObjectGrants {

   logit("Enter subroutine showObjectGrants");

   my ($sql,$cursor,$text,$link);

   $sql = "$copyright
SELECT
   GRANTOR	\"Grantor\",
   GRANTEE	\"Grantee\",
   PRIVILEGE	\"Privilege\",
   GRANTABLE	\"Grantable\"
FROM DBA_TAB_PRIVS
   WHERE TABLE_NAME = '$object_name'
   AND OWNER = '$schema'
ORDER BY GRANTEE, PRIVILEGE
";

   $text = "Grants for object $schema.$object_name";
   $link = "";
   DisplayTable($sql,$text,$link);

   logit("Exit subroutine showObjectGrants");

}

sub Button {

   logit("Enter subroutine Button");

   my $href		= shift;
   my $text		= shift;
   my $bgcolor		= shift;
   my $align		= shift;
   my $pixels		= shift;

   $align = "CENTER" unless $align;

   $pixels = 100 unless $pixels;

   print <<"EOF";
      </FONT>
      </FONT>
      <TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0 ALIGN=$align WIDTH=$pixels>
        <TR>
          <TD VALIGN="TOP" WIDTH=100%>
            <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1 WIDTH=100%>
              <TR ALIGN="CENTER">
                <TD BGCOLOR='$cellcolor'><B><FONT SIZE="$menufontsize">
EOF
   if ($href) {
      print "<A HREF=$href>$text</A>";
    } else {
      print "<FONT COLOR=$bordercolor>$text</FONT>";
   }
print <<"EOF"; 
                </B> 
                </TD>
              </TR>
            </TABLE>
          </TD>
        </TR>
      </TABLE>
      <TABLE WIDTH="100" CELLPADDING="1" CELLSPACING="0" BORDER="0">
        <TD></TD>
      </TABLE>
EOF

   print "<FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>";

   logit("Exit subroutine Button");

}

sub showIndextype {

   logit("Enter subroutine showIndextype");

   my ($sql,$text,$link);

# General indextype info

   $sql = "$copyright
SELECT
   INDEXTYPE_NAME					\"Indextype name\",
   IMPLEMENTATION_SCHEMA				\"Implementation schema\",
   IMPLEMENTATION_NAME					\"Implementation name\",
   IMPLEMENTATION_VERSION				\"Implementation version\",
   TO_CHAR(NUMBER_OF_OPERATORS,'999,999,999,999')	\"# operators\"
FROM DBA_INDEXTYPES
   WHERE INDEXTYPE_NAME = '$object_name'
   AND OWNER = '$schema'
";
   $text = "";
   $link = "";
   DisplayTable($sql,$text,$link);

   $sql = "$copyright
SELECT 
   INDEXTYPE_NAME					\"Indextype name\",
   BINDING#						\"Binding#\",
   OPERATOR_NAME					\"Operator name\"
FROM DBA_INDEXTYPE_OPERATORS
   WHERE INDEXTYPE_NAME = '$object_name'
   AND OWNER = '$schema'
   ORDER BY BINDING#
";
   $text = "Indextype operators";
   $link = "";
   DisplayTable($sql,$text,$link);

   logit("Exit subroutine showIndextype");

}

sub showLibrary {

   logit("Enter subroutine showLibrary");

   my ($sql,$text,$link);

# General library info

   $sql = "$copyright
SELECT
   LIBRARY_NAME				\"Library name\",
   FILE_SPEC				\"Filename\",
   DECODE(DYNAMIC,'N','No','Y','Yes')	\"Dynamic?\",
   STATUS				\"Status\"
FROM DBA_LIBRARIES
   WHERE LIBRARY_NAME = '$object_name'
   AND OWNER = '$schema'
";
   $text = "";
   $link = "";
   DisplayTable($sql,$text,$link);

   logit("Exit subroutine showLibrary");

}

sub showOperator {

   logit("Enter subroutine showOperator");

   my ($sql,$text,$link);

# General operator info

   $sql = "$copyright
SELECT
   OPERATOR_NAME				\"Operator name\",
   TO_CHAR(NUMBER_OF_BINDS,'999,999,999,999')	\"# Binds\"
FROM DBA_OPERATORS
   WHERE OPERATOR_NAME = '$object_name'
   AND OWNER = '$schema'
";
   $text = "";
   $link = "";
   DisplayTable($sql,$text,$link);

   $sql = "$copyright
SELECT 
   BINDING#					\"Binding#\",
   FUNCTION_NAME				\"Function name\",
   RETURN_SCHEMA				\"Return schema\",
   RETURN_TYPE					\"Return type\",
   IMPLEMENTATION_TYPE_SCHEMA			\"Imp type schema\",
   IMPLEMENTATION_TYPE				\"Imp type\"
FROM DBA_OPBINDINGS
   WHERE OPERATOR_NAME = '$object_name'
   AND OWNER = '$schema'
   ORDER BY BINDING#
";

   $text = "Bindings";
   $link = "";
   DisplayTable($sql,$text,$link);

   logit("Exit subroutine showOperator");

}

sub showQueue {

   logit("Enter subroutine showQueue");

   my ($sql,$text,$link);

# General queue info

   $sql = "$copyright
SELECT
   NAME						\"Name\",
   QUEUE_TABLE					\"Queue table\",
   QID						\"ID\",
   QUEUE_TYPE					\"Type\",
   TO_CHAR(MAX_RETRIES,'999,999,999,999')	\"Max retries\",
   TO_CHAR(RETRY_DELAY,'999,999,999,999')	\"Retry delay\",
   ENQUEUE_ENABLED				\"Enqueue enabled?\",
   DEQUEUE_ENABLED				\"Dequeue enabled?\",
   RETENTION					\"Retention\",
   USER_COMMENT					\"User comment\"
FROM DBA_QUEUES
   WHERE NAME = '$object_name'
   AND OWNER = '$schema'
";
   $text = "";
   $link = "";
   DisplayTable($sql,$text,$link);

   logit("Exit subroutine showQueue");

}

sub recordCount {

   logit("Enter subroutine recordCount");

   my ($dbh,$sql,$cursor,$record,$count);
  
   $dbh = shift; 
   $sql = shift;

   logit("   SQL = $sql");

   $cursor = $dbh->prepare($sql) or logit("   ERROR: $DBI::errstr");
   $cursor->execute;
   while ($record = $cursor->fetchrow_array) {
      $count++;
   }
   $cursor->finish;
   logit("   Count = $count");

   logit("Exit subroutine recordCount");

   return($count);

}

sub rmanBackups {

   logit("Enter subroutine rmanBackups");

   my ($sql,$cursor,$text,$infotext,$link,$command,$count);
   my ($recid,$stamp,$set_stamp,$filenum,$name,$inc_level);
   my ($ckpt_chng,$ckpt_time,$mar_cor,$med_cor,$log_cor);
   my ($df_blocks,$blocks,$comp_time,$rowcount,$backupfile_record);
   my ($set_count,@backupfile_array);

   $command = $query->param('command') || shift;

   logit("   Command is $command");

# Commands:
#   menu:			Show menu
#   datafiles_added:		Show datafiles added since last backup
#   last_backup:		Show most recent information about backups of existing datafiles
#   unrecoverable_datafiles:	Show datafiles which have had UNRECOVERABLE operations performed
#				on them since their last backup.

   if ($command eq "menu") {

         text("All backup information in this section is taken from the controlfiles.");

         Button("$scriptname?database=$database&object_type=RMANBACKUPS&command=last_backup TARGET=body","Current datafile backups","$headingcolor","CENTER","200");

# Check for datafiles added since last backup..

      $sql = "$copyright
SELECT
   COUNT(*)
FROM V\$DATAFILE
   WHERE CREATION_CHANGE# NOT IN (
SELECT DISTINCT CREATION_CHANGE# 
   FROM V\$BACKUP_DATAFILE
)
";
      $count = recordCount($dbh,$sql);

      if ($count) {
         Button("$scriptname?database=$database&object_type=RMANBACKUPS&command=datafiles_added TARGET=body","Datafiles never backed up","$headingcolor","CENTER","200");
      }

# Check for datafiles which are backed up but have been dropped.
# No good, can't get filename.

#      $sql = "$copyright
#SELECT
#   COUNT(*)
#FROM V\$BACKUP_DATAFILE
#   WHERE CREATION_CHANGE#
#NOT IN (SELECT CREATION_CHANGE#
#FROM V\$DATAFILE)
#";
#      $count = recordCount($dbh,$sql);

#      if ($count) {
#         Button("$scriptname?database=$database&object_type=RMANBACKUPS&command=datafiles_dropped TARGET=body","Datafiles backed up but dropped","$headingcolor","CENTER","200");
#      }

# Check for files which have had unrecoverable operations run against them.
# This does not mean you can't recover the file, it means that you can't 
# recover the transactions if you lose the datafile.

      $sql = "$copyright
SELECT COUNT(*)
FROM
   V\$DATAFILE VD,
(
SELECT BD.CREATION_CHANGE#, MAX(BD.COMPLETION_TIME) COMPLETION_TIME
FROM
   V\$BACKUP_DATAFILE BD
GROUP BY BD.CREATION_CHANGE#
) VBD
WHERE VBD.CREATION_CHANGE# = VD.CREATION_CHANGE#
AND VD.UNRECOVERABLE_TIME > VBD.COMPLETION_TIME
";
      $count = recordCount($dbh,$sql);

      if ($count) {
         Button("$scriptname?database=$database&object_type=RMANBACKUPS&command=unrecoverable_datafiles TARGET=body","Unrecoverable datafiles","$headingcolor","CENTER","200");
      }
   }

   if ($command eq "datafiles_added") {

      $sql = "
SELECT
   NAME								\"Filename\",
   TO_CHAR(CREATION_TIME,'Mon DD YYYY @ HH24:MI:SS')		\"Date created\"
FROM V\$DATAFILE
   WHERE CREATION_CHANGE# NOT IN (
SELECT DISTINCT CREATION_CHANGE# FROM V\$BACKUP_DATAFILE
)
";
      $text = "Datafile(s) which have been added but not backed up.";
      $link = "$scriptname?database=$database&object_type=DATAFILE";
      $infotext = "No datafiles have been added since the last backup.";
      DisplayTable($sql,$text,$link,$infotext);

   }

#   if ($command eq "datafiles_dropped") {

#      $sql = "$copyright
#SELECT
#   NAME
#FROM V\$DATAFILE
#   WHERE CREATION_CHANGE# IN (
#SELECT CREATION_CHANGE#
#FROM V\$BACKUP_DATAFILE
#   WHERE CREATION_CHANGE#
#NOT IN (SELECT CREATION_CHANGE#
#FROM V\$DATAFILE))
#";

#      $text = "Datafiles which are backed up but have been dropped.";
#      $link = "$scriptname?database=$database&object_type=DATAFILE";
#      $infotext = "";
#      DisplayTable($sql,$text,$link,$infotext);

#   }


   if ($command eq "last_backup") {

      my ($numfiles,$totalalloc,$totalwritt,$diff,$lowscn,$highscn,$cursor,$moretext);

      $sql = "
SELECT
TO_CHAR(COUNT(*),'999,999,999,999')										\"# Files\",
TO_CHAR(SUM(VBD.DATAFILE_BLOCKS*VBD.BLOCK_SIZE),'999,999,999,999,999,999')                                      \"Total bytes allocated\",
TO_CHAR(SUM(VBD.BLOCKS*VBD.BLOCK_SIZE),'999,999,999,999')                                      		         \"Total bytes written\",
TO_CHAR((SUM(VBD.DATAFILE_BLOCKS*VBD.BLOCK_SIZE) - SUM(VBD.BLOCKS*VBD.BLOCK_SIZE)),'999,999,999,999')   \"Difference\",
TO_CHAR(MIN(VBD.CHECKPOINT_CHANGE#),'999,999,999,999,999')							\"Lowest SCN\",
TO_CHAR(MAX(VBD.CHECKPOINT_CHANGE#),'999,999,999,999,999')							\"Highest SCN\"
FROM V\$BACKUP_DATAFILE VBD, V\$DATAFILE VDF,
(SELECT
   CREATION_CHANGE#,
   MAX(COMPLETION_TIME) COMPLETION_TIME
FROM V\$BACKUP_DATAFILE 
   WHERE CREATION_CHANGE# IN (
SELECT CREATION_CHANGE# FROM V\$DATAFILE)
GROUP BY CREATION_CHANGE#
) QUERY1
   WHERE VBD.CREATION_CHANGE# = VDF.CREATION_CHANGE#
   AND VBD.CREATION_CHANGE# = QUERY1.CREATION_CHANGE#
   AND VBD.COMPLETION_TIME = QUERY1.COMPLETION_TIME
";

      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      ($numfiles,$totalalloc,$totalwritt,$diff,$lowscn,$highscn) = $cursor->fetchrow_array;
      $cursor->finish;

      $sql = "
SELECT
DECODE(DUMMY,'X','$numfiles')		\"# Files\",
DECODE(DUMMY,'X','$totalalloc')		\"Total bytes allocated\",
DECODE(DUMMY,'X','$totalwritt')		\"Total bytes written\",
DECODE(DUMMY,'X','$diff')		\"Difference\",
DECODE(DUMMY,'X','$lowscn')		\"Lowest SCN\",
DECODE(DUMMY,'X','$highscn')		\"Highest SCN\"
   FROM DUAL
";

      if ($lowscn eq $highscn) {
         $moretext = "This appears to be an offline (cold) backup.";
      } else {
         $moretext = "This appears to be an online (hot) backup, or possibly incomplete.";
      }

      $text = "Space information pertaining to backed up datafiles.<BR>These values do not include datafiles which may have been added since the last backup.<BR>$moretext";
      $link = "";
      $infotext = "No backups found.";
      DisplayTable($sql,$text,$link,$infotext);

      $sql = "
SELECT
   VDF.NAME								\"Filename\",
   TO_CHAR(VBD.COMPLETION_TIME,'Mon DD YYYY @ HH24:MI:SS')		\"Completion time\",
   TO_CHAR(VBD.DATAFILE_BLOCKS*VBD.BLOCK_SIZE,'999,999,999,999')	\"File size\",
   TO_CHAR(VBD.BLOCKS*VBD.BLOCK_SIZE,'999,999,999,999')			\"Bytes written\",
   VBD.INCREMENTAL_LEVEL						\"Level\",
   TO_CHAR(VBD.CHECKPOINT_CHANGE#,'999,999,999,999,999')		\"Ckpt change#\",
   TO_CHAR(VBD.CHECKPOINT_TIME,'Mon DD YYYY @ HH24:MI:SS')		\"Checkpoint time\",
   VBD.MARKED_CORRUPT							\"Mrkd crpt\",
   VBD.MEDIA_CORRUPT							\"Media crpt\",
   VBD.LOGICALLY_CORRUPT						\"Lgcl crpt\"
FROM V\$BACKUP_DATAFILE VBD, V\$DATAFILE VDF,
(SELECT
   CREATION_CHANGE#,
   MAX(COMPLETION_TIME) COMPLETION_TIME
FROM V\$BACKUP_DATAFILE
   WHERE CREATION_CHANGE# IN (
SELECT CREATION_CHANGE# FROM V\$DATAFILE)
GROUP BY CREATION_CHANGE#
) QUERY1
   WHERE VBD.CREATION_CHANGE# = VDF.CREATION_CHANGE#
   AND VBD.CREATION_CHANGE# = QUERY1.CREATION_CHANGE#
   AND VBD.COMPLETION_TIME = QUERY1.COMPLETION_TIME
   ORDER BY 2 DESC, 5 DESC, 6 DESC
";

      $text = "Most recent backup information for existing datafiles.";
      $link = "$scriptname?database=$database&object_type=DATAFILE";
      $infotext = "No backups found.";
      $count = DisplayTable($sql,$text,$link,$infotext);

   }

   if ($command eq "unrecoverable_datafiles") {

      $sql = "$copyright
SELECT VD.NAME
FROM
   V\$DATAFILE VD,
(
SELECT BD.CREATION_CHANGE#, MAX(BD.COMPLETION_TIME) COMPLETION_TIME
FROM
   V\$BACKUP_DATAFILE BD
GROUP BY BD.CREATION_CHANGE#
) VBD
WHERE VBD.CREATION_CHANGE# = VD.CREATION_CHANGE#
AND VD.UNRECOVERABLE_TIME > VBD.COMPLETION_TIME
";

      $text = "Datafiles which have had UNRECOVERABLE operations performed on them since their last backup.";
      $link = "$scriptname?database=$database&object_type=RMANBACKUPS&command=datafile";
      $infotext = "";
      $count = DisplayTable($sql,$text,$link,$infotext);
   }

   logit("Exit subroutine rmanBackups");

}

sub rmanMonitor {

   logit("Enter subroutine rmanMonitor");

   my ($sql,$cursor,$refreshrate,$text,$infotext,$link);

   $refreshrate = $ENV{'AUTO_REFRESH'} || "10";

   print <<"EOF";
<FORM METHOD="POST" ACTION="$scriptname">
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE=HIDDEN NAME=database    VALUE=$database>
  <INPUT TYPE=HIDDEN NAME=object_type VALUE=$object_type>
  <INPUT TYPE=HIDDEN NAME=refreshrate VALUE=$refreshrate>
  <INPUT TYPE=SUBMIT NAME=foobar      VALUE=\"AutoRefresh ($refreshrate)\">
</FORM>
<P>
EOF

   $sql = "
SELECT
   INST_ID					\"Instance\",
   SID						\"Sid\",
   SERIAL#					\"Serial#\",
   CONTEXT					\"Context\",
   TO_CHAR(SOFAR,'999,999,999,999')		\"Blocks read\",
   TO_CHAR(TOTALWORK,'999,999,999,999')		\"Blocks total\",
   TO_CHAR(TOTALWORK-SOFAR,'999,999,999,999')	\"Blocks remaining\",
   ROUND(SOFAR/TOTALWORK*100,2)			\"% Complete\"
FROM GV\$SESSION_LONGOPS
   WHERE COMPNAM = 'dbms_backup_restore'
   AND ROUND(SOFAR/TOTALWORK*100,2) < 100
   ORDER BY 1 DESC
" if $oracle8; 

   $sql = "
SELECT
   INST_ID					\"Instance\",
   SID						\"Sid\",
   SERIAL#					\"Serial#\",
   OPNAME					\"Operation\",
   TO_CHAR(SOFAR,'999,999,999,999')		\"Blocks read\",
   TO_CHAR(TOTALWORK,'999,999,999,999')		\"Blocks total\",
   TO_CHAR(TOTALWORK-SOFAR,'999,999,999,999')	\"Blocks remaining\",
   ROUND(SOFAR/TOTALWORK*100,2)			\"% Complete\"
FROM GV\$SESSION_LONGOPS
   WHERE OPNAME LIKE 'RMAN%'
   AND OPNAME NOT LIKE '%aggregate%'
   AND TOTALWORK != 0
   AND SOFAR <> TOTALWORK
" if ($oracle8i || $oracle9i || $oracle10);


   $text = "RMAN backup channel progress...";
   $infotext = "No RMAN channels are active at this time...";
   $link = "";
   DisplayTable($sql,$text,$link,$infotext);

   logit("Exit subroutine rmanMonitor");

}

sub rmanCatalogQuery {

   logit("Enter subroutine rmanCatalogQuery");

   my ($sql1,$cursor1,$sql2,$cursor2,$owner,$count,$version,$command);
   my ($text,$infotext,$link,$sql,$cursor);

   $command = $query->param('command') || "";

   logit("   Command is $command");

   if ($command eq "listdbs") {

      # List the databases contained in the catalog

      $sql = "$copyright
SELECT
   NAME							\"DB name\",
   TO_CHAR(RESETLOGS_TIME,'Month DD, YYYY - HH24:MI')	\"Last resetlogs\"
FROM $schema.RC_DATABASE
   ORDER BY 1
";

      $text = "Database(s) registered in this catalog.";
      $infotext = "RMAN catalog owned by $schema contains no databases.";
      $link = "$scriptname?database=$database&schema=$schema&object_type=RMANCATALOGQUERY&command=latestresyncs";
      DisplayTable($sql,$text,$link,$infotext);

   }

   if ($command eq "latestresyncs") {

      my ($db_key,$dbinc_key);
      
      # List information about the database chosen.

      $sql = "$copyright
SELECT
   RESYNC_TYPE  	                                        \"Resync type\",
   TO_CHAR(MAX(RESYNC_TIME),'Month DD, YYYY - HH24:MI')      \"Resync time\"
FROM $schema.RC_RESYNC
   WHERE DB_NAME = '$object_name'
GROUP BY RESYNC_TYPE
ORDER BY 2
";

      $text = "Latest resyncs for database $object_name.";
      $infotext = "No resyncs for database $object_name on record.";
      $link = "";
      DisplayTable($sql,$text,$link,$infotext);

      # List information about the most recent backup of each distinct datafile etc.

      # First, get the DBINC_KEY, used for most queries.

#         $sql = "
#SELECT
#   DB_KEY,DBINC_KEY
#FROM $schema.DBINC
#   WHERE DATABASE_NAME = '$object_name'
#";

      $sql = "
SELECT
   DB_KEY,DBINC_KEY
FROM $schema.DBINC
   WHERE DB_NAME = '$object_name'
";

      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      ($db_key,$dbinc_key) = $cursor->fetchrow_array;
      $cursor->finish;

      $sql = "
SELECT
   DFATT.FNAME								\"File name\",
   TO_CHAR(MAX(BDF.COMPLETION_TIME),'Mon DD YYYY @ HH24:MI:SS')		\"Completion time\"
FROM $schema.DFATT DFATT, $schema.BDF BDF
   WHERE DFATT.DBINC_KEY = $dbinc_key
   AND DFATT.DBINC_KEY = BDF.DBINC_KEY
   AND DFATT.FILE# = BDF.FILE#
GROUP BY DFATT.FNAME
ORDER BY 2 DESC
";

      $text = "Latest datafile backups for database $object_name.";
      $infotext = "No backups for database $object_name in catalog.";
      $link = "";
      DisplayTable($sql,$text,$link,$infotext);

   }

   unless ($command) {

      # No command is passed, so show the catalog(s)

      text("The following RMAN catalog(s) exist.");

      print << "EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Catalog owner</A></TH>
        <TH BGCOLOR='$headingcolor' ALIGN=LEFT><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Catalog version</TH>
EOF

      $sql1 = "$copyright
SELECT
   OWNER
FROM DBA_TABLES
   WHERE TABLE_NAME = 'RCVER'
";

      $cursor1 = $dbh->prepare($sql1);
      $cursor1->execute;
      while ($owner = $cursor1->fetchrow_array) {
         $sql2 = "$copyright
SELECT
   VERSION
FROM $owner.RCVER
";

         $cursor2 = $dbh->prepare($sql2);
         next unless ($cursor2);
         $cursor2->execute;
         $version = $cursor2->fetchrow_array;
         $cursor2->finish;
         logit("   Seems to be a RMAN catalog, version $version owned by $owner");
         print "<TR><TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=RMANCATALOGQUERY&schema=$owner&command=listdbs>$owner</A></TD>\n";
         print "<TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$version</TD></TR>\n";
      }
      $cursor1->finish;
      print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF
   }
   logit("Exit subroutine rmanCatalogQuery");
}

sub dbAdmin {

   logit("Enter subroutine dbAdmin");

   my ($sql,$cursor,$username,$password,$deftablespace,$temptablespace,$profile);
   my ($cascade,$copyuser,$bytes,$tablespace_name,$privilege,$granted_role);
   my ($admin_option,$default_role,@params,$param,$sid,$serial,$obj_name);
   my ($owner,$object_type,$object_id,$foo,@audits,$audit,$audits,$by,$whenever);
   my ($whenevercount,@objects,@privileges,@users,$moresql,$users,$wheneversql);
   my ($status,$text,@default_roles,$roles);

   $username		= $query->param('username') || "";
   $password		= $query->param('password') || "";
   $deftablespace	= $query->param('deftablespace') || "";
   $temptablespace	= $query->param('temptablespace') || "";
   $profile		= $query->param('profile') || "";
   $cascade		= $query->param('cascade') || "";
   $copyuser		= $query->param('copyuser') || "";

   logit("   Command is $object_name");

   # Change a system parameter on the fly.

   if ($object_name eq "changeparameter") {
      my $parameter	= $query->param('parameter');
      my $value		= $query->param('value');
      $sql = "
SELECT 
   DECODE(TYPE,
		1,'NOQOUTE',
		2,'QUOTE',
		3,'NOQUOTE')
    FROM V\$PARAMETER WHERE NAME = '$parameter'
";
      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      my $param_type = $cursor->fetchrow_array;
      logit("   Parameter type is $param_type.");
      $cursor->finish; 
      if ($param_type eq "NOQUOTE")  {
         runSQL($dbh,"ALTER SYSTEM SET $parameter = $value");
      } else {
         runSQL($dbh,"ALTER SYSTEM SET $parameter = '$value'");
      }
   }

   # Kill one or more sessions.

   if ($object_name eq "killsessions") {
      @params = $query->param;
      foreach $param(@params) {
         if ($param =~ /^killsession/) {
            $param =~ s/killsession_//;
            ($sid,$serial) = split("~", $param);
            runSQL($dbh,"ALTER SYSTEM KILL SESSION '$sid,$serial'");
         }
      }
   }

   if ($object_name eq "alter_rollbacks") {
      my $shrinkto = $query->param('shrinkto');
      my ($rbs,$command);
      logit("   Shrinkto value is set to: $shrinkto");
      @params = $query->param;
      foreach $param(@params) {
         logit("   Param = $param");
         if ($param =~ /^alter/) {
            ($foo,$rbs,$command) = split("~", $param);
            logit("   RBS: $rbs, Command: $command");
            if ($command eq "online") {
               runSQL($dbh,"ALTER ROLLBACK SEGMENT $rbs ONLINE");
            }
            if ($command eq "offline") {
               runSQL($dbh,"ALTER ROLLBACK SEGMENT $rbs OFFLINE");
            }
            if ($command eq "shrink") {
               if ($shrinkto) { 
                  runSQL($dbh,"ALTER ROLLBACK SEGMENT $rbs SHRINK TO $shrinkto");
               } else {
                  runSQL($dbh,"ALTER ROLLBACK SEGMENT $rbs SHRINK");
               }
            }
         }
      }
   }

   if ($object_name eq "dependencies") {

      my ($link,$infotext);

      @params = $query->param;
      foreach $param(@params) {
         logit("   Param = $param");
         if ($param =~ /^dependency/) {
            ($foo,$object_id) = split("~", $param);

            showDependencies($object_id);

            print "<HR WIDTH=75%>";

         }
      }
   }

   if ($object_name eq "compile") {
      @params = $query->param;
      logit("   Params: @params");
      foreach $param(@params) {
         if ($param =~ /^compile_/) {
            logit("   Param: $param");
            ($foo,$object_id) = split("_", $param);
            logit("   Object_id = $object_id");
            $sql = "$copyright
SELECT
   OBJECT_TYPE,
   OWNER,
   OBJECT_NAME
FROM DBA_OBJECTS 
   WHERE OBJECT_ID = $object_id
";
            $cursor = $dbh->prepare($sql);
            $cursor->execute;
            ($object_type,$owner,$obj_name) = $cursor->fetchrow_array;
            $cursor->finish;
            if ($object_type eq "PACKAGE BODY") {
               runSQL($dbh,"ALTER PACKAGE $owner.$obj_name COMPILE BODY");
            } else {
               runSQL($dbh,"ALTER $object_type $owner.$obj_name COMPILE");
            }
            logit("   Object $object_type $owner.$obj_name COMPILE");
            $sql = "$copyright
SELECT
   STATUS
FROM DBA_OBJECTS
   WHERE OBJECT_NAME = '$obj_name'
   AND OBJECT_TYPE = '$object_type'
   AND OWNER = '$owner'
";

            $cursor = $dbh->prepare($sql);
            $cursor->execute;
            $status = $cursor->fetchrow_array;
            $cursor->finish;

            if ($status eq "INVALID") {

               $sql = "$copyright
SELECT
   LINE         \"Line\",
   POSITION     \"Position\",
   TEXT         \"Text\"
FROM DBA_ERRORS
   WHERE NAME = '$obj_name'
   AND TYPE = '$object_type'
   AND OWNER = '$owner'
ORDER BY SEQUENCE
";
               $text = "Object $owner.$obj_name still has errors..";
               DisplayTable($sql,$text);
               print "<P>\n";
            }
         }
      }
   }

   if ($object_name eq "changepassword") {
      $sql = "
ALTER USER $username IDENTIFIED BY $password
";
      runSQL($dbh,$sql)
   }

  if ($object_name eq "unlockuser") {
      $sql = "
ALTER USER $username ACCOUNT UNLOCK
";
      runSQL($dbh,$sql)
   }

   if ($object_name eq "createuser") {
      $sql = "
CREATE USER $username 
   IDENTIFIED BY $password
   DEFAULT TABLESPACE $deftablespace
   TEMPORARY TABLESPACE $temptablespace
   PROFILE $profile
";

      runSQL($dbh,$sql)

   }

   if ($object_name eq "dropuser") {

      if ($cascade) {
         $sql = "
DROP USER $username CASCADE
";
       } else {
      $sql = "
DROP USER $username
";
      }

      runSQL($dbh,$sql)
   }

   if ($object_name eq "removestmtaudits") {
      @params = $query->param;
      foreach $param(@params) {
         if ($param =~ /^removeaudit/) {
            $param =~ s/removeaudit_//;
            ($privilege,$username) = split("~", $param);
            $privilege =~ s/\+/ /g;
            if ($username) {
               $sql = "
NOAUDIT $privilege BY $username
";
            } else {
               $sql = "
NOAUDIT $privilege
";
            }
            logit("   Remove audits: $sql");
            runSQL($dbh,$sql);
         }
      }
   }

   if ($object_name eq "removeobjaudits") {
      @params = $query->param;
      foreach $param(@params) {
         if ($param =~ /^removeaudit/) {
            $param =~ s/removeaudit_//;
            ($owner,$obj_name) = split("~", $param);
            $sql = "
NOAUDIT ALL ON $owner.$obj_name
";
            logit("   Remove audits: $sql");
            runSQL($dbh,$sql);
         }
      }
   }

   if ($object_name eq "dostatementaudits") {
      @params = $query->param;
      logit("   Params: @params");
      @users = $query->param('users');
      $users = join(",", @users);
      logit("   Users: $users");
      @privileges = $query->param('privilege');
      logit("   Privileges: @privileges");
      unless (@privileges) {
         message("You must select at least one privilege..");
         Footer();
      }
      $by = $query->param('by');
      if ($users) {
         $moresql = " BY $users";
      }
      if ($by) {
         $moresql .= " BY $by";
      }
      foreach $param(@params) {
         if ($param =~ /whenever~/) {
            $whenevercount++; 
            ($foo,$whenever) = split("~", $param);
            if ($whenever eq "NOTSUCCESSFUL") {
               $wheneversql = " WHENEVER NOT SUCCESSFUL";
            } 
            if ($whenever eq "SUCCESSFUL") {
               $wheneversql = " WHENEVER SUCCESSFUL";
            }
         }
      }
      if ($whenevercount == 1) {
         $moresql .= $wheneversql;
      }
      foreach $privilege (@privileges) {
         $sql = "
AUDIT $privilege$moresql
";
         logit("   $sql");
         runSQL($dbh,$sql)
      }
      
   }

   if ($object_name eq "doschemaaudits") {
      @params = $query->param;
      logit("   Params: @params");
      @objects = $query->param('object');
      logit("   Objects: @objects");
      $by = $query->param('by');
      foreach $param(@params) {
         if ($param =~ /audit~/) {
            ($foo,$audit) = split("~", $param);
            push @audits, $audit;
         }
         if ($param =~ /whenever~/) {
            $whenevercount++;
            ($foo,$whenever) = split("~", $param);
            if ($whenever eq "NOTSUCCESSFUL") {
               $whenever = "NOT SUCCESSFUL";
            }
         }
      }
      logit("   Audits = @audits");
      $audits = join(",", @audits);
      foreach $obj_name(@objects) {
         if ($whenevercount != 1) {
            $sql = "
AUDIT $audits ON $obj_name BY $by
";
         } else {
            $sql = "
AUDIT $audits ON $obj_name BY $by WHENEVER $whenever
";
         }
         logit("   $sql");
         runSQL($dbh,$sql)
      }
   }

   if ($object_name eq "copyuser") {

      $sql = "
SELECT 
   DEFAULT_TABLESPACE,
   TEMPORARY_TABLESPACE,
   PROFILE
FROM DBA_USERS 
   WHERE USERNAME = '$copyuser'
";

      $cursor=$dbh->prepare($sql);
      $cursor->execute;
      ($deftablespace,$temptablespace,$profile) = $cursor->fetchrow;
      $cursor->finish;

      $sql = "
CREATE USER $username
   IDENTIFIED BY $password
   DEFAULT TABLESPACE $deftablespace
   TEMPORARY TABLESPACE $temptablespace
   PROFILE $profile
";

      runSQL($dbh,$sql);

      $sql = "
SELECT
   MAX_BYTES,
   TABLESPACE_NAME
FROM DBA_TS_QUOTAS
   WHERE USERNAME = '$copyuser'
";

      $cursor=$dbh->prepare($sql);
      $cursor->execute;
      while (($bytes,$tablespace_name) = $cursor->fetchrow) {
         $bytes = "UNLIMITED" if ($bytes eq "-1");
         $sql = "
ALTER USER $username QUOTA $bytes on $tablespace_name
";
         runSQL($dbh,$sql);
      }

      $sql = "$copyright
SELECT
   GRANTED_ROLE,
   ADMIN_OPTION,
   DEFAULT_ROLE
FROM DBA_ROLE_PRIVS
   WHERE GRANTEE = '$copyuser'
";

      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      while (($granted_role,$admin_option,$default_role) = $cursor->fetchrow) {
         $sql = "
GRANT $granted_role TO $username
";
         $sql .= " WITH ADMIN OPTION" if ($admin_option eq "YES");
         runSQL($dbh,$sql);
         if ($default_role eq "YES") {
            push @default_roles, $granted_role;
         }
      }
      $cursor->finish;
      if (@default_roles) {
         $roles = join(",",@default_roles);
         runSQL($dbh,"ALTER USER $username DEFAULT ROLE $roles");
      }

      $sql = "$copyright
SELECT
   PRIVILEGE,
   ADMIN_OPTION
FROM DBA_SYS_PRIVS 
   WHERE GRANTEE = '$copyuser'
"; 

      $cursor = $dbh->prepare($sql);
      $cursor->execute;
      while (($privilege,$admin_option) = $cursor->fetchrow) {
         $sql = "
GRANT $privilege TO $username
";
         $sql .= " WITH ADMIN OPTION" if ($admin_option eq "YES");
         runSQL($dbh,$sql);
      }
   }

   logit("Exit subroutine dbAdmin");

}

sub showDependencies {

   logit("Enter subroutine showDependencies");

   my $object_id = shift;

   my ($sql,$cursor,$text,$link,$infotext,$object_type,$owner,$object_name);

   $sql = "
SELECT
   OBJECT_NAME,
   OBJECT_TYPE,
   OWNER
FROM DBA_OBJECTS
   WHERE OBJECT_ID = $object_id
";
   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   ($object_name,$object_type,$owner) = $cursor->fetchrow_array;
   $cursor->finish;


  $sql = "
SELECT
   OBJECT_NAME          \"Object name\",
   OBJECT_TYPE          \"Object type\",
   OWNER                \"Owner\"
FROM DBA_OBJECTS
   WHERE OBJECT_ID IN (
SELECT
   P_OBJ#
FROM SYS.DEPENDENCY\$
   WHERE D_OBJ# = $object_id
   )
ORDER BY 3,2,1
";
   $text = "$object_type $owner.$object_name depends on the following objects.";
   $link = "";
   $infotext = "$object_type $owner.$object_name has no dependencies on other objects.";
   ObjectTable($sql,$text,$infotext);

   $sql = "
SELECT
   OBJECT_NAME          \"Object name\",
   OBJECT_TYPE          \"Object type\",
   OWNER                \"Owner\"
FROM DBA_OBJECTS
   WHERE OBJECT_ID IN (
SELECT
   D_OBJ#
FROM SYS.DEPENDENCY\$
   WHERE P_OBJ# = $object_id
   )
ORDER BY 3,2,1
";
   $text = "The following objects depend on $object_type $owner.$object_name.";
   $link = "";
   $infotext = "No other objects have dependencies on $object_type $owner.$object_name.";
   ObjectTable($sql,$text,$infotext);

   logit("Exit subroutine showDependencies");

}


sub healthCheckMenu {

   logit("Enter subroutine healthCheck");

   text("The following reports will be run on each instance that Oracletool has valid connection information for.");

   Button("$scriptname?database=$database&object_type=HEALTHCHECK&command=tsgraph TARGET=body","Tablespace usage","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=HEALTHCHECK&command=datafiles TARGET=body","Datafile information","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=HEALTHCHECK&command=sessions TARGET=body","Session activity","$headingcolor","CENTER","200");
   Button("$scriptname?database=$database&object_type=HEALTHCHECK&command=rollbacks TARGET=body","Rollback segment information","$headingcolor","CENTER","200");

   logit("Exit subroutine healthCheck");

}

sub healthCheck {

   logit("Enter subroutine healthCheck");

   my (@databases,$username,$password);
   my ($sessionid,$command);

   $command = $query->param('command');

   $norefreshbutton = "Nope";

   @databases = GetTNS();

   foreach $database(@databases) {

      $sessionid = cookie("$database.sessionid");

      logit("Cookie for instance $database returned $sessionid");

      if ($sessionid) {
         ($username,$password) = decodeSessionid($sessionid);
         logit("   Username: $username Password: $password");
         if ($username && $password) {
            $dbh = dbConnect($database,$username,$password,"skiperrorcheck");
            if ($dbh) {
               getDbVersion($dbh);

               if ($command eq "tsgraph") {
                  text("<CENTER>Tablespace allocation graph for instance $database.");
                  showTSgraph();
               }
               if ($command eq "sessions") {
                  text("<CENTER>Session summary for instance $database.");
                  topSessions();
               }
               if ($command eq "rollbacks") {
                  text("<CENTER>Rollback segment information for instance $database.");
                  showRollbacks();
               }
               if ($command eq "datafiles") {
                  text("<CENTER>Datafile information for instance $database.");
                  dbFileList();
               }
               $dbh->disconnect;
               print "<P><HR WIDTH=90%><P>";
            } else {
               logit("   Error connecting to $database: $DBI::errstr");
            }
         }
      }
   }
}

sub jobScheduler {

   logit("Enter subroutine jobScheduler");

   my ($sql,$cursor,$command,$username,$password,$database);
   my ($jobnum,$what,$next_date,$interval,$no_parse,$nls_date_format);

   $command	= $query->param('command')  || "";
   $username	= $query->param('username') || "";
   $password	= $query->param('password') || "";
   $database	= $query->param('database') || "";
   $jobnum	= $query->param('jobnum') || "";

   $nls_date_format = "Mon DD YYYY HH24:MI";

   logit("   Command is $command");
   logit("   Date format is $nls_date_format");

   unless ($command eq "connect") {

      logit("   Connecting to $database");
      $dbh = dbConnect($database,$username,$password,"skiperrorcheck");
      unless ($dbh) {
         message("There was a problem connecting to $database. Error is $DBI::errstr");
         logit("There was a problem connecting to $database. Error is $DBI::errstr");
         Footer();
      }

      $sql = "Alter session set nls_date_format = '$nls_date_format'";
      $dbh->do($sql);

   }

   if ($command eq "delete") {

      logit("Deleting job number $jobnum");

      $cursor = $dbh->prepare(q{
BEGIN
   SYS.DBMS_JOB.REMOVE(?);
END;
});
      $cursor->bind_param(1, $jobnum);

      $cursor->execute;
      logit("   Execute: $DBI::errstr");
      $cursor->finish;

      $command = "showjobs";

   }
      

   if ($command eq "savejob") {

      my ($what,$next_date,$interval); 

      $what		= $query->param('what');
      $next_date	= $query->param('next_date');
      $interval		= $query->param('interval');

      if ($jobnum) {

         logit("   We are editing, not submitting");

         $cursor = $dbh->prepare(q{
BEGIN
   SYS.DBMS_JOB.CHANGE(?,?,?,?);
END;
});

#         $what		=~ s/'/''/g;
#         $what		= "'$what'";
#         $next_date	= "'$next_date'";
#         $interval	= "'$interval'";

         logit("   JobNum $jobnum What $what Next date $next_date Interval $interval"); 
         logit("DBMS_JOB.CHANGE($jobnum,$what,$next_date,$interval)");

         $cursor->bind_param(1, $jobnum);
         $cursor->bind_param(2, $what);
         $cursor->bind_param(3, $next_date);
         $cursor->bind_param(4, $interval);

         $cursor->execute;
         logit("   Execute: $DBI::errstr");
         if ($DBI::errstr) {
            message("There was a problem changing job # $jobnum. Error follows..<BR>$DBI::errstr");
            $cursor->finish;
            Footer();
         }
         $cursor->finish;

      } else {

         logit("   We are submitting, not editing.");

         $cursor = $dbh->prepare(q{
BEGIN
   SYS.DBMS_JOB.SUBMIT(?,?,?,?);
END;
});
         logit("   Prepare: $DBI::errstr");

#         $what		=~ s/'/''/g;
#         $what		= "'$what'";
#         $next_date	= "TO_DATE('$next_date','$nls_date_format')";
#         $interval	= "'$interval'";

         logit("   JobNum $jobnum What $what Next date $next_date Interval $interval"); 
         logit("DBMS_JOB.SUBMIT(:jobnum,$what,$next_date,$interval)");

         $cursor->bind_param_inout(1, \$jobnum, 10);
         $cursor->bind_param(2, $what);
         $cursor->bind_param(3, $next_date);
         $cursor->bind_param(4, $interval);

         $cursor->execute;
         logit("   Execute: $DBI::errstr");
         if ($DBI::errstr) {
            message("There was a problem submitting job # $jobnum. Error follows..<BR>$DBI::errstr");
            $cursor->finish;
            Footer();
         }
         $cursor->finish;

         logit("   The new job number is $jobnum.");

      }

     $command = "showjobs";

   }

   if ($command eq "addoredit") {

      my $subcommand = $query->param('subcommand');
      logit("   Subcommand = $subcommand");
      logit("   Jobnum = $jobnum");

      ($what,$next_date,$interval) = "";

      if ($subcommand eq "edit") {
         $sql = "
SELECT
   WHAT,
   NEXT_DATE,
   INTERVAL
FROM USER_JOBS
   WHERE JOB = $jobnum
";
         $cursor = $dbh->prepare($sql);
         $cursor->execute;
         ($what,$next_date,$interval) = $cursor->fetchrow_array;
         $cursor->finish;
         logit("What $what Next date $next_date Interval $interval");
      } else {

         $what	= $query->param('what') || "";

         $sql = "
SELECT
   SYSDATE
FROM DUAL
";
         $cursor = $dbh->prepare($sql);
         $cursor->execute;
         $next_date = $cursor->fetchrow_array;
         $cursor->finish;

         $interval = "sysdate+1/24";

      }

      print <<"EOF";
<B>
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="JOBSCHEDULER">
  <INPUT TYPE="HIDDEN" NAME="command" VALUE="savejob">
  <INPUT TYPE="HIDDEN" NAME="username" VALUE="$username">
  <INPUT TYPE="HIDDEN" NAME="password" VALUE="$password">
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="jobnum" VALUE="$jobnum">
EOF

      if ($subcommand eq "edit") {
         text("Edit job # $jobnum");
      } else {
         text("Add a job");
      }

      print <<"EOF";

   Examples of value for "interval"..<P>

   Every 5 minutes (approx.): SYSDATE+1/24/12<BR>
   Every hour: SYSDATE+1/24<BR>
   Every two hours: SYSDATE+1/12<BR>
   Once a day: SYSDATE+1<P>

   What to execute: Example: DBMS_UTILITY.ANALYZE_DATABASE('ESTIMATE');<BR><INPUT TYPE=TEXT NAME=what VALUE="$what" SIZE=50 MAXLENGTH=4000><P>
   The next date to execute:<BR><INPUT TYPE=TEXT NAME=next_date VALUE="$next_date" SIZE=20 MAXLENGTH=4000><P>
   The interval:<BR><INPUT TYPE=TEXT NAME=interval VALUE=$interval SIZE=20 MAXLENGTH=4000>
  <P>
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Submit">
</FORM>
EOF

      Footer();
   }

   if ($command eq "connect") {

      my ($sid,@sids);

      @sids = GetTNS();

      text("Schedule or alter a job via the Oracle DBMS_JOB package.");

      print <<"EOF";
<B>
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="JOBSCHEDULER">
  <INPUT TYPE="HIDDEN" NAME="command" VALUE="showjobs">
Choose the database where the job will run..
  <SELECT SIZE=1 NAME=database>
EOF
      logit("   Printed menu");
      foreach $sid(@sids) {
         print "<OPTION>$sid\n";
      }

      logit("   Printed list");

      print <<"EOF";
  </SELECT>
  <P>
  Enter the name of the schema that owns or will own the job. This is the schema that the job will run under.
  <BR>
  Username <INPUT TYPE=TEXT MAXLENGTH=30 SIZE=10 NAME=username>&nbsp;&nbsp;Password <INPUT TYPE=PASSWORD MAXLENGTH=30 SIZE=10 NAME=password>
  <P>
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Next >>">
</FORM>
EOF
   }

   if ($command eq "showjobs") {

      my ($sql,$text,$link,$infotext,$count);
      my ($jobnum,$lastrun,$nextrun,$interval,$command,$broken);

      text("Schedule or alter a job via the Oracle DBMS_JOB package.<BR>Database $database, schema $username");
      text("Note: Be sure that the initialization parameter \"job_queue_processes\" is set to at least 1. Otherwise, your job will never run.");
      Button("$scriptname?database=$database&object_type=JOBSCHEDULER&command=addoredit&subcommand=add&jobnum=$jobnum&username=$username&password=$password","Add a job","$headingcolor","CENTER","200");

      $count = recordCount($dbh,"SELECT COUNT(*) FROM USER_JOBS");

      unless ($count > 0) {

         text("There are no jobs currently scheduled");

      } else {

         $sql = "
SELECT
   SYSDATE	\"Current time\"
FROM DUAL
";
         $text = "";
         $infotext = "";
         $link = "";
         DisplayTable($sql,$text,$link,$infotext);

         print "<P>";

         $sql = "
SELECT
   JOB							\"Job#\",
   LAST_DATE	\"Last run\",
   NEXT_DATE	\"Next run\",
   INTERVAL						\"Interval\",
   WHAT							\"Command\",
   BROKEN						\"Broken?\"
FROM USER_JOBS";

      print <<"EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Edit</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Del</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Job#</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Last run</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Next run</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Interval</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Command</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Broken?</TH>
EOF

         $cursor = $dbh->prepare($sql);
         $cursor->execute;

         while (($jobnum,$lastrun,$nextrun,$interval,$command,$broken) = $cursor->fetchrow_array) {
            print <<"EOF";
        <TR>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=JOBSCHEDULER&command=addoredit&subcommand=edit&jobnum=$jobnum&username=$username&password=$password>Edit</A></TD>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?database=$database&object_type=JOBSCHEDULER&command=delete&jobnum=$jobnum&username=$username&password=$password>Delete</A></TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$jobnum</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$lastrun</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$nextrun</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$interval</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$command</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$broken</TD>
        </TR>
EOF
         }
         $cursor->finish;
         print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF
         Footer();

      }
   }
}

sub myOracletoolCreate {

   logit("Enter subroutine myOracletoolCreate");

# This sub does not expect a valid cookie to log into
# the repository.

   my ($sessionid,$myusername,$mypassword,$mydatabase,$command);

   $command = shift;
   
   $command = $query->param('command') unless $command;

   logit("   Command is $command");

   if ($command eq "create_repository1") {
       # This gets executed right after the cookie is saved successfully.

#      if (myOracletoolRepositoryExists()) {
#         logit("Repositroy already exists, redirecting to the menu.");
#         myOracletool();
#      }

      text("</CENTER>Oracletool will now attempt to create the repository.<BR>In the case that this repository already exists, the existing objects will not be be overwritten or deleted.");
      print <<"EOF";
<B>
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="MYORACLETOOL">
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="command" VALUE="create_repository2">
  <P>
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Next >>">
</FORM>
EOF

   }

   if ($command eq "savecookie") {

      logit("   Attempting to create the MyOracletool repository..");

      my ($cookie1,$cookie2,$path,$message,$url,$duration,$bgline);

      $mydatabase = $query->param('mydatabase') || "";
      $myusername = $query->param('myusername') || "";
      $mypassword = $query->param('mypassword') || "";
 
      unless ($myusername && $mypassword) {

         logit("   Username was not specified!") unless $myusername;
         logit("   Password was not specified!") unless $mypassword;

         ErrorPage("You must specify a username and password.");

         Footer();
      }

   # Check that the username and password are valid for this database.

      logit("   Checking username ($myusername) and password for database $mydatabase");

      my $data_source = "dbi:Oracle:$mydatabase";

      my $testdbh = DBI->connect($data_source,$myusername,$mypassword,{PrintError=>0});
      unless ($testdbh) {
         logit("   Test login to repository failed, Reason $DBI::errstr");
         ErrorPage("Your login to $mydatabase with the username $myusername failed for the following reason: $DBI::errstr");
         Footer();
      } else {
         logit("   Test login to repository was successful");
         $testdbh->disconnect;
         logit("   Disconnected from repository.");
      }

      $sessionid = buildSessionid($myusername,$mypassword);
      $path = dirname($scriptname);

      logit("My Oracletool sesionid is being set to $sessionid");

      $cookie1 = cookie(-name=>"MyOracletool",-value=>"$sessionid",-expires=>"+10y");
      $cookie2 = cookie(-name=>"MyOracletoolDB",-value=>"$mydatabase",-expires=>"+10y");
      print header(-cookie=>[$cookie1,$cookie2]);
      $message     = "Your password for My Oracletool has been updated.<BR>Oracletool will restart with a connection to instance $database.";
      $duration    = "3";
      $url         = "$scriptname?database=$database&object_type=MYORACLETOOLCREATE&command=create_repository1&database=$database";

      $bgline = "<BODY BGCOLOR=$bgcolor>\n";

      if ($bgimage) {
         if ((-e "$ENV{'DOCUMENT_ROOT'}/$bgimage") && (-r "$ENV{'DOCUMENT_ROOT'}/$bgimage")) {
            logit("   Background image is $ENV{'DOCUMENT_ROOT'}/$bgimage and is readable");
            $bgline = "<BODY BACKGROUND=$bgimage>\n";
         }
      }

      print <<"EOF";
<HTML>
  <HEAD>
    <TITLE>Password has been updated.</TITLE>
    <META HTTP-EQUIV="Refresh" Content="$duration;URL=$url">
  </HEAD>
  $bgline
    <FONT FACE="$font" SIZE="$fontsize" COLOR="$fontcolor">
    <CENTER>
      $message
    </CENTER
  </BODY
</HTML>
EOF
      $testdbh->disconnect if $testdbh;
      Footer();

   }

   if ($command eq "newuser") {

      my @sids = GetTNS();
      my $sid;

      text("</CENTER>&nbsp;&nbsp;&nbsp;My Oracletool allows you to store scripts and information in a centralized repository. For instance, perhaps you have a particular query you like to run on several of your databases. You can store this query in your repository and run it while connected to any of your databases. In order to use My Oracletool, you need the \"CREATE TABLE\" privilege in one of your databases. Oracletool will create several tables in a schema that you specify (in one database only) to store this information and can access it no matter what database you are connected to at any given time. Give it a try!");

      logit("   Printed text");
      print <<"EOF";
<B>
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="MYORACLETOOLCREATE">
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="command" VALUE="savecookie">
Choose a database for your repository..
  <SELECT SIZE=1 NAME=mydatabase>
EOF
      logit("   Printed menu");
      foreach $sid(@sids) {
         print "<OPTION>$sid\n";
      }

      logit("   Printed list");

      print <<"EOF";
  </SELECT>
  <P>
  Enter a schema name to own the repository. This schema must already exist!
  <BR>
  Username <INPUT TYPE=TEXT MAXLENGTH=30 SIZE=10 NAME=myusername>&nbsp;&nbsp;Password <INPUT TYPE=PASSWORD MAXLENGTH=30 SIZE=10 NAME=mypassword>
  <P>
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Next >>">
</FORM>
EOF

   }

   logit("Exit subroutine myOracletoolCreate");
   Footer();

}

sub myOracletoolRepositoryExists {

   my (@repository_objects,$all_objects,$all_object_count,$recordcount);

   logit("Enter subroutine myOracletoolRepositoryExists");

   @repository_objects = (
                          "OT_SCRIPTS",
                          "OT_SCRIPT_SOURCE",
                          "OT_NOTES",
                          "OT_NOTE_TEXT",
                          "OT_FILES",
                          "OT_CONTACTS",
                          "OT_PREFERENCES"
                         );

   $all_objects = "('" . join("','", @repository_objects) . "')";
   $all_object_count = $#repository_objects+1;

   logit("All objects = $all_objects Count = $all_object_count");

   logit("      Checking for the existence of the repository objects.");
   $recordcount = recordCount($mydbh,"SELECT OBJECT_NAME FROM USER_OBJECTS WHERE OBJECT_NAME IN $all_objects");
   unless ( $recordcount == $all_object_count ) {
      logit("One or more repository objects NOT found. Returning.");
      return(0);
   } else {
      logit("All repository objects found. Returning.");
      return(@repository_objects);
   }
}

sub myOracletool {

   logit("Enter subroutine myOracletool");

# This sub expects a valid cookie to log into the repository.
# Unless the command is to create the repository, all of the
# repository tables are expected to exist.

   my ($sessionid,$myusername,$mypassword,$mydatabase,$command);
   my (@repository_objects,$script,$recordcount,$note,$id);

   $command = shift || $query->param('command') || "menu";

   logit("   Command is $command");

   # Get the required cookies.

   $sessionid = cookie("MyOracletool");
   $mydatabase = cookie("MyOracletoolDB");

   ($myusername,$mypassword) = decodeSessionid($sessionid);

   $mydbh = dbConnect($mydatabase,$myusername,$mypassword,"skiperrorcheck");

   if ($sessionid && $mydatabase) {
      logit("      Checking connectivity");
      unless ($mydbh) {
         logit("      Connection failed! Error returned is $DBI::errstr");
         message("Login failed: reason: $DBI::errstr");
         myOracletoolCreate("newuser");
      } else {
         logit("      Connection to My Oracletool repository ($myusername\@$mydatabase) successful!");
      }
    } else {
      myOracletoolCreate("newuser");
   }
   
   $mydbh->do("Alter session set nls_date_format='$nls_date_format'");
         
   if ($command eq "delete1") {
   # Prepare to delete the contents of the repository, drop the tables.
      my @objects = myOracletoolRepositoryExists();
      my ($object);
      if ($#objects) {
         logit("   There are $#objects objects to remove from this repository.");
         logit("   @objects");
         text("</CENTER>The following objects will be dropped from the schema $myusername at connection $mydatabase.");
         foreach $object(@objects) {
            text("$object");
         }
         print <<"EOF";
<B>
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="MYORACLETOOL">
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="command" VALUE="delete2">
  <P>
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Next >>">
</FORM>
EOF
       } else {
         message("The repository appears to have objects missing. No action taken.");
      }
   }

   if ($command eq "delete2") {
   # Delete the contents of the repository, drop the tables.
      my @objects = myOracletoolRepositoryExists();
      my ($object,$sql);
      if ($#objects) {
         logit("   Removing $#objects objects to remove from this repository.");
         logit("   @objects");
         foreach $object(@objects) {
            $sql = "DROP TABLE $object CASCADE CONSTRAINTS";
            doSQL($mydbh,$sql);
            logit("   Dropped (or attempted to drop) $object");
         }
         message("The repository for schema $myusername at connection $mydatabase has been removed.");
         $command = "expire";   
      } else {
         message("The repository appears to have objects missing. No action taken.");
      }
   }

   if ($command eq "expire") {
   # This prints the first page for expiring the myOracletool cookie.
      text("</CENTER>Oracletool will now remove the stored connection info for your repository. This allows you to connect to, or create a separate repository. The repository objects owned by $myusername at connection $mydatabase will not be removed..");
      print <<"EOF";
<B>
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="MYORACLETOOL">
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="myoracletoolexpire" VALUE="Yep">
  <P>
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Next >>">
</FORM>
EOF

   }

   if ($command eq "fileadmin") {

      logit("   In fileadmin section.");

      my $param		= $query->param('command1');
      my $id		= $query->param('id');
      my $headertype	= $query->param('headertype');

      if ($param eq "del") {
         logit("      Comand is delete file ID $id");
         my ($sql);
         $sql = "
DELETE FROM OT_FILES WHERE ID = $id
";
         $mydbh->do($sql);
         $command = "files";
      }

      if ($param eq "view") {
         my ($sql,$cursor,$bytes,$data);
         logit("      Gonna view file ID $id");
         $sql = "
SELECT BYTES FROM OT_FILES WHERE ID = $id
";
         $cursor = $mydbh->prepare($sql);
         $cursor->execute;
         $bytes = $cursor->fetchrow_array;
         $cursor->finish;
         logit("      File is $bytes in size, mime_type is $headertype");
         $bytes++;
         $mydbh->{LongReadLen} = $bytes;
         $mydbh->{LongTruncOk} = 1;

         $sql = "
SELECT DATA FROM OT_FILES WHERE ID = $id
";
         $cursor = $mydbh->prepare($sql) or logit("      Error: $DBI::errstr");
         $cursor->execute;
         while ($data = $cursor->fetchrow_array) {
            print STDOUT $data;
         }
         $cursor->finish;
         exit;
      }
   }

   if ($command eq "noteadmin") {

      my ($param,$data,$sql,$notetext,$cursor,$id,$note);
      my ($count);

      logit("   In noteadmin section.");

      $param	= $query->param('command1');
      $id	= $query->param('id');

      logit("   Command is $param, Note ID is $id.");

      if ($param eq "view") {
         logit("   Viewing note ID $id.");

         $mydbh->do("UPDATE OT_NOTES SET ACCESSES = ACCESSES+1 WHERE ID = $id");

         $sql = "
SELECT
   NAME
FROM OT_NOTES
   WHERE ID = $id
";
         $cursor = $mydbh->prepare($sql);
         $cursor->execute;
         $note = $cursor->fetchrow_array;
         $cursor->finish;

         $sql = "
SELECT
   TEXT
FROM OT_NOTE_TEXT
   WHERE ID = $id
ORDER BY LINE
";
         $cursor = $mydbh->prepare($sql);
         $cursor->execute;
         while ($data = $cursor->fetchrow_array) {
            $notetext = "$notetext$data";
         }
         $cursor->finish;
         Button("$scriptname?object_type=MYORACLETOOL&command=notes&database=$database","Notes","$headingcolor","CENTER","200");
         text("Note name: $note");
         # Check for any attached files.
         $count = recordCount($mydbh,"Select filename from OT_FILES WHERE NOTE_ID=$id");
         if ($count) {
            my ($filename,$created,$viewed,$description,$mime_type,$bytes);
            $sql = "
SELECT
   ID,
   FILENAME,
   TO_CHAR(CREATED,'Mon DD YYYY @ HH24:MI:SS'),
   VIEWED,
   DESCRIPTION,
   MIME_TYPE,
   TO_CHAR(BYTES,'999,999,999,999,999,999')
FROM OT_FILES
   WHERE NOTE_ID=$id
   ORDER BY 2 DESC
";

            print <<"EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>View</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>File name</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Description</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Size</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Created</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Del</TH>
EOF

            $cursor = $mydbh->prepare($sql);
            $cursor->execute;

            while (($id,$filename,$created,$viewed,$description,$mime_type,$bytes) = $cursor->fetchrow_array) {
               print <<"EOF";
        <TR>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?object_type=MYORACLETOOL&command=fileadmin&command1=view&id=$id&headertype=$mime_type&filename=$filename&database=$database>view</A></TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$filename</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$description</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$bytes</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$created</TD>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?object_type=MYORACLETOOL&command=fileadmin&command1=del&id=$id&database=$database>del</A></TD>
        </TR>
EOF
            }
            $cursor->finish;
            print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF
         }
         my $size = $fontsize+1;
print <<"EOF";
<BR>
<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TR>
          <TD BGCOLOR='$cellcolor'>
            <FONT COLOR='$fontcolor' SIZE='$size' FACE='$font'>
            </CENTER>
            <PRE>$notetext</PRE>
          </TD>
        </TR>
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF
      }

      if ($param eq "edit") {
         logit("   Editing note ID $id.");
         $mydbh->do("UPDATE OT_NOTES SET ACCESSES = ACCESSES+1 WHERE ID = $id");
         $command = "newnote";
      }

      if ($param eq "del") {
         logit("   Deleting note ID $id.");
         doSQL($mydbh,"DELETE FROM OT_NOTES WHERE ID = $id");
         doSQL($mydbh,"DELETE FROM OT_NOTE_TEXT WHERE ID = $id");
         doSQL($mydbh,"DELETE FROM OT_FILES WHERE NOTE_ID = $id");
         $command = "notes";
      }
   }

   if ($command eq "scriptadmin") {

# They have put a check mark next to a script, either
# to execute it, edit it, or delete it.

      my (@params,$param,$data,$sql,$sqlscript,$cursor);

      logit("   In scriptadmin section.");

      @params = $query->param;
      foreach $param(@params) {
         logit("   Param: $param");
         if ($param =~ /^edit/) {
            ($param,$id) = split("~", $param);
            $script = $query->param('edit');
            logit("   Editing script ID $id.");
            $command = "newsql";
         }
         if ($param =~ /^exec/) {
            ($param,$id) = split("~", $param);
            logit("   Executing script ID $id.");
            $sql = "
SELECT
   TEXT
FROM OT_SCRIPT_SOURCE
   WHERE ID = $id
ORDER BY LINE
";
            $cursor = $mydbh->prepare($sql);
            $cursor->execute;
            while ($data = $cursor->fetchrow_array) {
               $sqlscript = "$sqlscript$data";
            }
            $cursor->finish;
#            text("Script name: $script");
            $sql = "UPDATE OT_SCRIPTS SET EXECUTIONS = EXECUTIONS+1 WHERE ID = $id"; 
            logit("Execution count update: $sql");
            $mydbh->do($sql);

            $sqlscript =~ s/\&lt\;/\</g;
            $sqlscript =~ s/\&gt\;/\>/g;
            $sqlscript =~ s/&#39;/'/g;
            $sqlscript =~ s/&#34;/"/g;

            logit("RUNNING SQL $sqlscript");
            runSQL($dbh,$sqlscript);
            $sqlscript = "";
         }
         if ($param =~ "^del") {
            ($param,$id) = split("~", $param);
            logit("   Deleting script ID $id.");
            doSQL($mydbh,"DELETE FROM OT_SCRIPTS WHERE ID = $id");
            doSQL($mydbh,"DELETE FROM OT_SCRIPT_SOURCE WHERE ID = $id");
            $command = "sql";
         }
      }
   }

   if ($command eq "addnote" || $command eq "editnote") {

# Adds newly entered note to the repository.

      my ($name,$description,$notetext,$cursor,$sql);
      my ($piece_length,$piece_count,$piece,$accesses);
      my ($filename,$oldid);

      $id		= $query->param('id');
      $name		= $query->param('name');
      $notetext		= $query->param('notetext');
      $filename		= $query->param('filename');
      $accesses		= 0;

      # Fix up the data for display purposes.
      $name =~ s/\</\&lt\;/g;
      $name =~ s/\>/\&gt\;/g;
      $name =~ s/'/&#39;/g;
      $name =~ s/"/&#34;/g;

      $notetext =~ s/\</\&lt\;/g;
      $notetext =~ s/\>/\&gt\;/g;
      $notetext =~ s/'/&#39;/g;
      $notetext =~ s/"/&#34;/g;

      if ($command eq "addnote") {
         unless ($name && $notetext) {
            message("All fields must be filled in. Please use the \"Back\" button on your browser and try again."); 
         }
      } else {
         unless ($notetext) {
            message("Please enter the script text. Please use the \"Back\" button on your browser and try again.");
         }
      }

      if ($command eq "editnote") {

         logit("Deleting old note from the repository for script $name.");

         $sql = "SELECT ACCESSES FROM OT_NOTES WHERE ID = $id";
         $cursor = $mydbh->prepare($sql);
         $cursor->execute;
         $accesses = $cursor->fetchrow_array;
         $cursor->finish;

         $sql = "DELETE FROM OT_NOTES WHERE ID = $id";
         logit("   SQL: $sql");
         $mydbh->do($sql);

         $sql = "DELETE FROM OT_NOTE_TEXT WHERE ID = $id";
         logit("   SQL: $sql");
         $mydbh->do($sql);

         # Keep the ID number, to update any attachments for this note.
         $oldid = $id;

      }

      logit("Adding note name $name Text: $notetext");

      $sql = "SELECT MAX(ID)+1 FROM OT_NOTES";
      $cursor = $mydbh->prepare($sql);
      $cursor->execute;
      $id = $cursor->fetchrow_array;
      $cursor->finish;
      $id = 1 unless $id;

      logit("   ID of new note is $id");

      $sql = "UPDATE OT_FILES SET NOTE_ID = $id where NOTE_ID = $oldid";
      $mydbh->do($sql);

      $sql = "INSERT INTO OT_NOTES (ID,NAME,ACCESSES) VALUES (?,?,?)";
      $cursor = $mydbh->prepare($sql);
      logit("   Error: $DBI::errstr");
      $cursor->execute($id,$name,$accesses);
      logit("   Error: $DBI::errstr");
      $cursor->finish;

      $piece_length = 2000;
      $piece_count  = 1;

      while ($notetext) {
         logit("   Piece count is $piece_count");
         $piece = substr($notetext,0,$piece_length);
         substr($notetext,0,$piece_length) = "";
         $sql = "INSERT INTO OT_NOTE_TEXT (ID,LINE,TEXT) VALUES(?,?,?)";
	 logit("   Preparing insert piece $piece_count");
         my $foo = length($piece);
         logit("   Length of piece is $foo");
         $foo = length($name);
         logit("   Length of name is $foo");
         $cursor = $mydbh->prepare($sql) or logit("$DBI::errstr");
         logit("   Executing insert piece $piece_count");
         $cursor->execute($id,$piece_count,$piece) or logit("$DBI::errstr");
         logit("   Finishing insert piece $piece_count");
         $cursor->finish or logit("$DBI::errstr");
         $piece_count++;
      }
      # If a file was attached, go add that as well. 
      if ($filename) {
         logit("   File $filename was attached, going to go add that.");
         $command = "addfile";
      } else {
         $command = "notes";
      }
   }

   if ($command eq "addsql" || $command eq "editsql") {

# Adds newly entered SQL script to the repository.

      my ($name,$description,$sqlscript,$cursor,$sql);
      my ($piece_length,$piece_count,$piece);

      $id               = $query->param('id');
      $name             = $query->param('name');
      $description      = $query->param('description');
      $sqlscript        = $query->param('sqlscript');

      # Fix up the data for display purposes.
      $name =~ s/\</\&lt\;/g;
      $name =~ s/\>/\&gt\;/g;
      $name =~ s/'/&#39;/g;
      $name =~ s/"/&#34;/g;

      $description =~ s/\</\&lt\;/g;
      $description =~ s/\>/\&gt\;/g;
      $description =~ s/'/&#39;/g;
      $description =~ s/"/&#34;/g;

      $sqlscript =~ s/\</\&lt\;/g;
      $sqlscript =~ s/\>/\&gt\;/g;
      $sqlscript =~ s/'/&#39;/g;
      $sqlscript =~ s/"/&#34;/g;

      if ($command eq "addsql") {
         unless ($name && $description && $sqlscript) {
            message("All fields must be filled in. Please use the \"Back\" button on your browser and try again."); 
         }
      } else {
         unless ($sqlscript) {
            message("Please enter the script text. Please use the \"Back\" button on your browser and try again.");
         }
      }

      if ($command eq "editsql") {

         logit("Deleting old SQL from the repository for script ID $id.");

         $sql = "DELETE FROM OT_SCRIPTS WHERE ID = $id";
         $mydbh->do($sql);

         $sql = "DELETE FROM OT_SCRIPT_SOURCE WHERE ID = $id";
         $mydbh->do($sql);

      }

#      logit("Checking for the existence of script named $name");

#      $sql = "SELECT COUNT(*) FROM OT_SCRIPTS WHERE NAME = '$name'";
#      $cursor = $mydbh->prepare($sql);
#      $cursor->execute;
#      $recordcount = $cursor->fetchrow_array;
#      $cursor->finish;
#      if ( $recordcount ) {
#         logit("   Script $name already exists.");
#         message("A script by the name of $name already exists. Please change the name.");
#         Footer();
#      }

      logit("Adding script name $name description $description SQL: $sqlscript");

      $sql = "SELECT MAX(ID)+1 FROM OT_SCRIPTS";
      $cursor = $mydbh->prepare($sql);
      $cursor->execute;
      $id = $cursor->fetchrow_array;
      $cursor->finish;
      $id = 1 unless $id;

      logit("   ID of new SQL script is $id");

      $sql = "INSERT INTO OT_SCRIPTS (ID,NAME,DESCRIPTION,EXECUTIONS) VALUES (?,?,?,?)";
      $cursor = $mydbh->prepare($sql);
      $cursor->execute($id,$name,$description,0);
      $cursor->finish;

      $piece_length = 2000;
      $piece_count  = 1;

      while ($sqlscript) {
         $piece = substr($sqlscript,0,$piece_length);
         substr($sqlscript,0,$piece_length) = "";
         $sql = "INSERT INTO OT_SCRIPT_SOURCE (ID,LINE,TEXT) VALUES(?,?,?)";
         $cursor = $mydbh->prepare($sql);
         $cursor->execute($id,$piece_count,$piece);
         $cursor->finish;
         $piece_count++;
      }
      $command = "sql"
   }

   if ($command eq "newfile") {

      my ($filename,$description,$foo);

      print "<B>Add MyOracletool file</B><BR>\n";
      if ($upload_limit) {
         $foo = commify($upload_limit);
         print "<B>Note that the upload limit per file is set to $foo bytes.</B><BR>\n";
      }

      print <<"EOF";
<FORM METHOD="POST" ACTION="$scriptname" method="post" enctype="multipart/form-data">
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  </CENTER>
  <B>File name</B>\&nbsp;\&nbsp;<INPUT TYPE=FILE NAME=filename SIZE=30 MAXLENGTH=100><P>
  <B>Description</B>\&nbsp;\&nbsp;<INPUT TYPE=TEXT NAME=description SIZE=30 MAXLENGTH=100><P>
  <INPUT TYPE=HIDDEN NAME=object_type VALUE=MYORACLETOOL>
  <INPUT TYPE=HIDDEN NAME=database VALUE=$database>
  <INPUT TYPE=HIDDEN NAME=command VALUE=addfile>
  <P>
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Upload">
</FORM>
EOF
   }

   if ($command eq "newnote") {

# Brings up a screen to add or edit a note.
# If "id" is passed to the CGI, an edit is assumed.
# Otherwise, it's a create.

      my ($id,$name,$description,$notetext);
      my ($data,$sql,$cursor);

      $id = $query->param('id');

      if ($id) {
 # We are editing, not creating
         logit("We are editing note ID $id, not creating a new note.");
         $command = "editnote";

         $sql = "
SELECT
   NAME
FROM OT_NOTES
   WHERE ID = $id
";
         $cursor = $mydbh->prepare($sql);
         $cursor->execute;
         $note = $cursor->fetchrow_array;
         $cursor->finish;

         $sql = "
SELECT
   TEXT
FROM OT_NOTE_TEXT
   WHERE ID = $id
ORDER BY LINE
";
         $cursor = $mydbh->prepare($sql);
         $cursor->execute;
         while ($data = $cursor->fetchrow_array) {
            $notetext = "$notetext$data";
         }
         $cursor->finish;
      } else {
 # We are creating
         logit("We are creating a new note.");
         $command = "addnote";
      }

      Button("$scriptname?object_type=MYORACLETOOL&command=notes&database=$database","Notes","$headingcolor","CENTER","200");

      print <<"EOF";
<FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
<P>
<FORM METHOD="POST" ACTION="$scriptname" enctype="multipart/form-data">
  </CENTER>
EOF
   if ($command eq "addnote") {
      print <<"EOF";
  <B>Note name</B>\&nbsp;\&nbsp;<INPUT TYPE=TEXT NAME=name SIZE=30 MAXLENGTH=100 VALUE="$note"><P>
EOF
   } else {
      print <<"EOF";
  <INPUT TYPE=HIDDEN NAME=name VALUE="$note">
  <CENTER>
  <B>$note</B><P>
EOF
   }
   print <<"EOF";
  <CENTER>
  <INPUT TYPE=HIDDEN NAME=object_type VALUE=MYORACLETOOL>
  <INPUT TYPE=HIDDEN NAME=command VALUE=$command>
  <INPUT TYPE=HIDDEN NAME=database VALUE=$database>
  <INPUT TYPE=HIDDEN NAME=id VALUE=$id>
  <TEXTAREA NAME=notetext ROWS=$textarea_h COLS=$textarea_w WRAP=OFF>$notetext</TEXTAREA>
  <P>
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Save note">
  <B>Attach a file</B>
  <INPUT TYPE=FILE NAME=filename SIZE=30 MAXLENGTH=100>
</FORM>
EOF
#      print <<"EOF";
#<B>Add MyOracletool file</B><P>
#<FORM METHOD="POST" ACTION="$scriptname" method="post" enctype="multipart/form-data">
#  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
#  </CENTER>
#  <B>File name</B>\&nbsp;\&nbsp;<INPUT TYPE=FILE NAME=filename SIZE=30 MAXLENGTH=100><P>
#  <B>Description</B>\&nbsp;\&nbsp;<INPUT TYPE=TEXT NAME=description SIZE=30 MAXLENGTH=100><P>
#  <INPUT TYPE=HIDDEN NAME=object_type VALUE=MYORACLETOOL>
#  <INPUT TYPE=HIDDEN NAME=command VALUE=addfile>
#  <INPUT TYPE=HIDDEN NAME=database VALUE=$database>
#  <P>
#  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Upload">
#</FORM>
#EOF

   }

   if ($command eq "newsql") {

# Brings up a screen to add or edit a SQL script.
# If "id" is passed to the CGI, an edit is assumed.
# Otherwise, it's a create.

      my ($name,$description,$sqlscript);
      my ($data,$sql,$cursor);

      if ($id) {

 # We are editing, not creating
         logit("We are editing script ID $id, not creating a new script.");
         $command = "editsql";
         $sql = "
SELECT
   NAME,
   DESCRIPTION 
FROM OT_SCRIPTS
   WHERE ID = $id
";
         $cursor = $mydbh->prepare($sql);
         $cursor->execute;
         ($script,$description) = $cursor->fetchrow_array;
         $cursor->finish;
         logit("Description is $description.");
         $sql = "
SELECT
   TEXT
FROM OT_SCRIPT_SOURCE
   WHERE ID = $id
ORDER BY LINE
";
         $cursor = $mydbh->prepare($sql);
         $cursor->execute;
         while ($data = $cursor->fetchrow_array) {
            $sqlscript = "$sqlscript$data";
         }
         $cursor->finish;
      } else {
 # We are creating
         logit("We are creating a new script.");
         $command = "addsql";
      }

      print <<"EOF";
<B>Add / Edit MyOracletool SQL scripts</B><P>
<FORM METHOD="POST" ACTION="$scriptname">
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  </CENTER>
EOF
   if ($command eq "addsql") {
      print <<"EOF";
  <B>Script name</B>\&nbsp;\&nbsp;<INPUT TYPE=TEXT NAME=name SIZE=30 MAXLENGTH=30 VALUE="$script"><P>
  <B>Description</B>\&nbsp;\&nbsp;<INPUT TYPE=TEXT NAME=description SIZE=50 MAXLENGTH=200 VALUE="$description"><P>
EOF
   } else {
      print <<"EOF";
  <INPUT TYPE=HIDDEN NAME=name VALUE="$script">
  <INPUT TYPE=HIDDEN NAME=description SIZE=50 MAXLENGTH=200 VALUE="$description">
  <B>Script name:</B>\&nbsp;\&nbsp;$script<BR>
  <B>Description:</B>\&nbsp;\&nbsp;$description<P>
EOF
   }
   print <<"EOF";
  <CENTER>
  <INPUT TYPE=HIDDEN NAME=object_type VALUE=MYORACLETOOL>
  <INPUT TYPE=HIDDEN NAME=command VALUE=$command>
  <INPUT TYPE=HIDDEN NAME=id VALUE=$id>
  <INPUT TYPE=HIDDEN NAME=database VALUE=$database>
  Paste or type the script in this area<P>
  <TEXTAREA NAME=sqlscript ROWS=$textarea_h COLS=$textarea_w WRAP=OFF>$sqlscript</TEXTAREA>
  <P>
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Save">
</FORM>
EOF

   }

   if ($command eq "addfile") {
      my ($sql,$cursor,$filename,$mime_type,$bytes,$data);
      my ($upload_filehandle,$description,$foo);
      my ($note_id,$name,$filesize);

      # Set $note_id and name if file is attached to a note.
      $note_id	= $id if ($id);
      $name	= $query->param('name');

      $sql = "SELECT MAX(ID)+1 FROM OT_FILES";
      $cursor = $mydbh->prepare($sql);
      $cursor->execute;
      $id = $cursor->fetchrow_array;
      $cursor->finish;
      $id = 1 unless $id;

      $filename		= $query->param("filename");
      if ($name) {
         $description = "Attachment ($name)";
      } else {
         $description	= $query->param("description");
      }
      logit("   Adding file name $filename to repository.");
      logit("   The upload limit is set to $upload_limit bytes per file.");
      $mime_type = $query->uploadInfo($filename)->{'Content-Type'};
#      $filesize = $query->uploadInfo($filename)->{'Size'};
#      logit("   Mime type is $mime_type, Size is $filesize.");
      logit("   Mime type is $mime_type.");
      # Get rid of leading slashes etc..
      $filename =~ s/.*[\/\\](.*)/$1/;
      $mime_type = $mydbh->quote($mime_type);
      $mime_type =~ s/^'//;
      $mime_type =~ s/'$//;
      $filename = $mydbh->quote($filename);
      $filename =~ s/^'//;
      $filename =~ s/'$//;
      $upload_filehandle = $query->upload("filename");
      while ( <$upload_filehandle> )
      {
         $data .= $_;
         if ($upload_limit) {
            if (length($data) > $upload_limit) {
               message("The file you are attempting to upload  ($filename) exceeds the upload file size limit ($upload_limit bytes)");
               Footer();
            }
         }
      }
      $bytes = length($data);
      logit("   Size of $filename is $bytes.");
      if ($note_id) {
         $sql = "
INSERT INTO OT_FILES (ID,NOTE_ID,FILENAME,DESCRIPTION,MIME_TYPE,BYTES,DATA) VALUES(?,?,?,?,?,?,?)
";
         logit("   ID: $id Filename: $filename Note ID: $note_id Description: $description Mime_type: $mime_type Bytes: $bytes");
         logit("   Preparing");
         $cursor = $mydbh->prepare($sql) or logit("   Error: $DBI::errstr");
         $cursor->bind_param(1,$id) or logit("   Error: $DBI::errstr");
         $cursor->bind_param(2,$note_id) or logit("   Error: $DBI::errstr");
         $cursor->bind_param(3,$filename) or logit("   Error: $DBI::errstr");
         $cursor->bind_param(4,$description) or logit("   Error: $DBI::errstr");
         $cursor->bind_param(5,$mime_type) or logit("   Error: $DBI::errstr");
         $cursor->bind_param(6,$bytes) or logit("   Error: $DBI::errstr");
         $cursor->bind_param(7,$data, { ora_type => 113 }) or logit("   Error: $DBI::errstr");
         $cursor->execute or logit("   Error: $DBI::errstr");
         $cursor->finish or logit("   Error: $DBI::errstr");

         $command = "notes";
      } else {
         $sql = "
INSERT INTO OT_FILES (ID,FILENAME,DESCRIPTION,MIME_TYPE,BYTES,DATA) VALUES(?,?,?,?,?,?)
";
         logit("   ID: $id Filename: $filename Description: $description Mime_type: $mime_type Bytes: $bytes");
         logit("   Preparing");
         $cursor = $mydbh->prepare($sql) or logit("   Error: $DBI::errstr");
         $cursor->bind_param(1,$id) or logit("   Error: $DBI::errstr");
         $cursor->bind_param(2,$filename) or logit("   Error: $DBI::errstr");
         $cursor->bind_param(3,$description) or logit("   Error: $DBI::errstr");
         $cursor->bind_param(4,$mime_type) or logit("   Error: $DBI::errstr");
         $cursor->bind_param(5,$bytes) or logit("   Error: $DBI::errstr");
         $cursor->bind_param(6,$data, { ora_type => 113 }) or logit("   Error: $DBI::errstr");
         $cursor->execute or logit("   Error: $DBI::errstr");
         $cursor->finish or logit("   Error: $DBI::errstr");

         $command = "files";
      }
   }

   if ($command eq "files") {
      my ($sql,$cursor,$filecount,$bytes,$mbytes);
      my ($text,$link,$infotext,$rows,$dbh,$filename_nospc);
      my ($filename,$mime_type,$created,$viewed);
      
      $sql = "
SELECT COUNT(*) FROM OT_FILES
";
      $cursor = $mydbh->prepare($sql);
      $cursor->execute;
      $filecount = $cursor->fetchrow_array;
      $cursor->finish;

            $sql = "
SELECT SUM(BYTES) FROM OT_FILES
";
      $cursor = $mydbh->prepare($sql);
      $cursor->execute;
      $bytes = $cursor->fetchrow_array;
      $cursor->finish;
      $mbytes = sprintf("%.2f",$bytes/1048576);
      $mbytes = commify($mbytes);
      $bytes = commify($bytes);

      Button("$scriptname?object_type=MYORACLETOOL&database=$database","Main menu","$headingcolor");
      text("There are $filecount files in the repository totaling $bytes bytes ($mbytes Mb).");
      Button("$scriptname?object_type=MYORACLETOOL&command=newfile&database=$database","Add a file","$headingcolor","CENTER","200");
      Footer() if $filecount == 0;

      $sql = "
SELECT 
   ID,
   FILENAME,
   CREATED,
   VIEWED,
   DESCRIPTION,
   MIME_TYPE,
   TO_CHAR(BYTES,'999,999,999,999,999,999')
FROM OT_FILES
   ORDER BY 3 DESC,2 DESC
";

      print <<"EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>View</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>File name</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Description</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Size</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Created</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Del</TH>
EOF

      $cursor = $mydbh->prepare($sql);
      $cursor->execute;

      while (($id,$filename,$created,$viewed,$description,$mime_type,$bytes) = $cursor->fetchrow_array) {
         $filename_nospc = $filename;
         $filename_nospc =~ s/ /%20/g;
         print <<"EOF";
        <TR>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?object_type=MYORACLETOOL&command=fileadmin&command1=view&id=$id&headertype=$mime_type&filename=$filename_nospc&database=$database>view</A></TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$filename</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$description</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$bytes</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$created</TD>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?object_type=MYORACLETOOL&command=fileadmin&command1=del&id=$id&database=$database>del</A></TD>
        </TR>
EOF
      }
      $cursor->finish;
      print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF
Footer();

   }

   if ($command eq "notes") {
      my ($sql,$cursor,$notecount,$id);
      my ($text,$link,$infotext,$rows,$dbh);
      my ($note,$desc,$created,$exec,$note_nospc);

      $sql = "
SELECT COUNT(*) FROM OT_NOTES
";
      $cursor = $mydbh->prepare($sql);
      $cursor->execute;
      $notecount = $cursor->fetchrow_array;
      $cursor->finish;
      Button("$scriptname?object_type=MYORACLETOOL&database=$database","Main menu","$headingcolor");
#      text("There are $notecount notes in the repository.");
      Button("$scriptname?object_type=MYORACLETOOL&command=newnote&database=$database","Add a note","$headingcolor","CENTER","200");
      if ($notecount == 0) {
         Footer();
      }

#   TO_CHAR(CREATED,'Mon DD YYYY @ HH24:MI:SS'),
      $sql = "
SELECT 
   ID,
   NAME,
   CREATED,
   ACCESSES
FROM OT_NOTES
   WHERE CREATED > SYSDATE-180
ORDER BY 3 DESC,4 DESC
";

      text("There are $notecount notes in the repository. Displaying added / edited last 180 days.");

      print <<"EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>View</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Edit</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Note</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Created / edited</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Del</TH>
EOF

      $cursor = $mydbh->prepare($sql);
      $cursor->execute;

      while (($id,$note,$created,$exec) = $cursor->fetchrow_array) {
         print <<"EOF";
        <TR>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?object_type=MYORACLETOOL&command=noteadmin&command1=view&id=$id&database=$database>view</A></TD>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?object_type=MYORACLETOOL&command=noteadmin&command1=edit&id=$id&database=$database>edit</A></TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$note</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$created</TD>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?object_type=MYORACLETOOL&command=noteadmin&command1=del&id=$id&database=$database>del</A></TD>
        </TR>
EOF
      }
      $cursor->finish;
      print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF
Footer();
   
   }

   if ($command eq "sql") {
      my ($sql,$cursor,$scriptcount,$id);
      my ($text,$link,$infotext,$rows,$dbh);
      my ($script,$desc,$created,$exec,$script_nospc);

      $sql = "
SELECT COUNT(*) FROM OT_SCRIPTS
";
      $cursor = $mydbh->prepare($sql);
      $cursor->execute;
      $scriptcount = $cursor->fetchrow_array;
      $cursor->finish;
      Button("$scriptname?object_type=MYORACLETOOL&database=$database","Main menu","$headingcolor");
      text("There are $scriptcount scripts in the repository.");
      Button("$scriptname?object_type=MYORACLETOOL&command=newsql&database=$database","Add a SQL script","$headingcolor","CENTER","200");
      Footer() if $scriptcount == 0;
      $sql = "
SELECT 
   ID,
   NAME,
   DESCRIPTION,
   TO_CHAR(CREATED,'Mon DD YYYY @ HH24:MI:SS'),
   EXECUTIONS
FROM OT_SCRIPTS
   ORDER BY 5 DESC
";

      print <<"EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <FORM METHOD=POST ACTION=$scriptname>
    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
    <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Submit">
    <P>
    <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="MYORACLETOOL">
    <INPUT TYPE="HIDDEN" NAME="command" VALUE="scriptadmin">
    <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Exec</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Edit</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Script</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Script Description</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Created / edited</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'># Executions</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Del</TH>
EOF

      $cursor = $mydbh->prepare($sql);
      $cursor->execute;

      while (($id,$script,$desc,$created,$exec) = $cursor->fetchrow_array) {
         print <<"EOF";
        <TR>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><INPUT TYPE=CHECKBOX NAME=exec~$id></TD>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?object_type=MYORACLETOOL&command=scriptadmin&edit~$id&database=$database>Edit</A></TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$script</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$desc</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$created</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$exec</TD>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?object_type=MYORACLETOOL&command=scriptadmin&del~$id&database=$database>Del</A></TD>
        </TR>
EOF
      }
      $cursor->finish;
      print <<"EOF";
      </TABLE>
    </TD>
  </TR>
  </FORM>
</TABLE>
EOF
Footer();
   
   }

   if ($command eq "create_repository2") {

      my ($sql);

      if (myOracletoolRepositoryExists()) {
         logit("Repository already exists, redirecting to the menu.");
         myOracletool("menu");
         Footer();
      }

      logit("Creating the repository.");

# Table for script name / descriptions.

      $sql = "
CREATE TABLE OT_SCRIPTS
   (
      ID		NUMBER,
      NAME              VARCHAR2(100),
      DESCRIPTION       VARCHAR2(200),
      CREATED           DATE DEFAULT SYSDATE,
      EXECUTIONS        NUMBER
   )
";
      doSQL($mydbh,$sql);
      logit("   Error: $DBI::errstr") if $DBI::errstr;

# Table for script source

      $sql = "
CREATE TABLE OT_SCRIPT_SOURCE
   (
      ID                NUMBER,
      LINE              NUMBER,
      TEXT              VARCHAR2(2000)
   )
";
      doSQL($mydbh,$sql);
      logit("   Error: $DBI::errstr") if $DBI::errstr;

# Table for note name / descriptions.

      $sql = "
CREATE TABLE OT_NOTES
   (
      ID		NUMBER,
      NAME              VARCHAR2(100),
      CREATED           DATE DEFAULT SYSDATE,
      ACCESSES          NUMBER DEFAULT 0
   )
";
      doSQL($mydbh,$sql);
      logit("   Error: $DBI::errstr") if $DBI::errstr;

# Table for note text.

      $sql = "
CREATE TABLE OT_NOTE_TEXT
   (
      ID                NUMBER,
      LINE              NUMBER,
      TEXT              VARCHAR2(2000)
   )
";
      doSQL($mydbh,$sql);
      logit("   Error: $DBI::errstr") if $DBI::errstr;

# Table for uploaded files.

      $sql = "
CREATE TABLE OT_FILES
   (
      ID		NUMBER,
      NOTE_ID		NUMBER,
      FILENAME		VARCHAR2(100),
      CREATED		DATE DEFAULT SYSDATE,
      VIEWED		NUMBER DEFAULT 0,
      DESCRIPTION	VARCHAR2(100),
      MIME_TYPE		VARCHAR2(100),
      BYTES		NUMBER,
      DATA		BLOB
   )
";
      doSQL($mydbh,$sql);
      logit("   Error: $DBI::errstr") if $DBI::errstr;

# Table for contact information.

   $sql = "
CREATE TABLE OT_CONTACTS
   (
      FNAME             VARCHAR2(30),
      MI                VARCHAR2(1),
      LNAME             VARCHAR2(30),
      DESCRIPTION       VARCHAR2(200),
      WPHONE            VARCHAR2(20), 
      HPHONE            VARCHAR2(20), 
      CPHONE            VARCHAR2(20), 
      PAGER             VARCHAR2(30)
   )
";
      doSQL($mydbh,$sql);
      logit("   Error: $DBI::errstr") if $DBI::errstr;

# Table for preferences.

   $sql = "
CREATE TABLE OT_PREFERENCES
   (
      NAME              VARCHAR2(20),
      VALUE             VARCHAR2(10)
   )
";
      doSQL($mydbh,$sql);
      logit("   Error: $DBI::errstr") if $DBI::errstr;

      $command = "menu";

   }

   if ($command eq "menu") {

      unless (myOracletoolRepositoryExists()) {
         myOracletoolCreate("create_repository1");
      }

      text("My Oracletool - Connected to the repository in $mydatabase owned by $myusername.");

      print "</FONT>\n";

      Button("$scriptname?object_type=MYORACLETOOL&command=sql&database=$database","SQL scripts <a href=$scriptname?object_type=MYORACLETOOL&command=newsql&database=$database>&nbsp;&nbsp;(Add)</a>","$headingcolor","CENTER","200");
      Button("$scriptname?object_type=MYORACLETOOL&command=notes&database=$database","Notes <a href=$scriptname?object_type=MYORACLETOOL&command=newnote&database=$database>&nbsp;&nbsp;(Add)</a>","$headingcolor","CENTER","200");
      Button("$scriptname?object_type=MYORACLETOOL&command=files&database=$database","Files <a href=$scriptname?object_type=MYORACLETOOL&command=newfile&database=$database>&nbsp;&nbsp;(Add)</a>","$headingcolor","CENTER","200");
      print <<"EOF";
      <P>
      <TABLE>
        <FORM METHOD=POST ACTION=$scriptname>
        <TR>
          <TD ALIGN=LEFT>
            <INPUT TYPE="TEXT" NAME="searchtext" SIZE="30">
          </TD>
          <TD ALIGN=RIGHT>
            <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="MYORACLETOOL">
            <INPUT TYPE="HIDDEN" NAME="command" VALUE="search">
            <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
            <INPUT TYPE="SUBMIT" VALUE="Search">
          </TD>
        </TR>
        <TR>
          <TD ALIGN=LEFT>
            Match any <INPUT TYPE=RADIO NAME=anyorall VALUE=any>&nbsp;&nbsp;
            Match all <INPUT TYPE=RADIO NAME=anyorall VALUE=all CHECKED>
          </TD>
          <TD>
          </TD>
        </TR>
        </FORM>
      </TABLE>
      <P><HR WIDTH=90%><P>
EOF
      Button("$scriptname?object_type=MYORACLETOOL&command=expire&database=$database","Remove connection info ($myusername\@$mydatabase)","$headingcolor","CENTER","200");
      Button("$scriptname?object_type=MYORACLETOOL&command=delete1&database=$database","Remove repository completely ($myusername\@$mydatabase)","$headingcolor","CENTER","200");
#      Button("$scriptname?object_type=MYORACLETOOL&command=notes&database=$database","Notes","$headingcolor","CENTER","200");
#      Button("$scriptname?object_type=MYORACLETOOL&command=contacts&database=$database","Contact list","$headingcolor","CENTER","200");

   }

   if ($command eq "search") {

      my ($keywords,$keyword,@keywords,$in_clause,$anyorall);
      my (@note_ids,$note_ids,@file_ids,$file_ids,@script_ids,$script_ids,$sql,$cursor,$id);
      my ($name,$count,$table,$andor,$note,$created,$exec);
      my ($note_count,$script_count,$desc);
    
      $keywords = $query->param('searchtext');
      $anyorall = $query->param('anyorall');

      # Split keywords by whitespace
      @keywords = split(/\s+/,$keywords);

      # Checking Notes
      if ($anyorall eq "any") {
         $andor = "or";
      }
      if ($anyorall eq "all") {
         $andor = "and";
      }

      # Checking NOTES
      $count		= 0;
      $note_count	= 0;
      foreach $keyword(@keywords) {
         unless ($count) {
            $sql = "Select distinct name,id from ot_notes where upper(name) like upper('\%$keyword\%')";
         } else {
            $sql .= " $andor upper(name) like upper('\%$keyword\%')";
         }
         $count++;
      } 
      logit("   SQL = $sql");
      $cursor = $mydbh->prepare($sql);
      $cursor->execute;
      while (($name,$id) = $cursor->fetchrow_array) {
         push @note_ids, $id;
         $note_count++;
         logit("  Name $name matches in table ot_notes");
      }
      $count = 0;
      foreach $keyword(@keywords) {
         unless ($count) {
            $sql = "Select distinct id from ot_note_text where upper(text) like upper('\%$keyword\%')";
         } else {
            $sql .= " $andor upper(text) like upper('\%$keyword\%')";
         }
         $count++;
      }   
      logit("   SQL = $sql");
      $cursor = $mydbh->prepare($sql);
      $cursor->execute;
      while ($id = $cursor->fetchrow_array) {
         push @note_ids, $id;
         $note_count++;
         logit("  ID $id matches in table ot_note_text");
      }
      logit("         Note ID's: @note_ids.");
      $note_ids = "(" . join(",", @note_ids) . ")";
      logit ("Query will use these ID's: $note_ids");
      # Displaying NOTES

      if ($note_count) {

         text("Notes which match the search criteria");

         $sql = "
SELECT 
   DISTINCT ID,
   NAME,
   TO_CHAR(CREATED,'Mon DD YYYY @ HH24:MI:SS'),
   ACCESSES
FROM OT_NOTES
   WHERE ID IN $note_ids
ORDER BY 4 DESC,3 DESC
";

         print <<"EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>View</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Edit</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Note</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Created / edited</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Del</TH>
EOF

         $cursor = $mydbh->prepare($sql);
         $cursor->execute;

         while (($id,$note,$created,$exec) = $cursor->fetchrow_array) {
            print <<"EOF";
        <TR>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?object_type=MYORACLETOOL&command=noteadmin&command1=view&id=$id&database=$database>view</A></TD>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?object_type=MYORACLETOOL&command=noteadmin&command1=edit&id=$id&database=$database>edit</A></TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$note</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$created</TD>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?object_type=MYORACLETOOL&command=noteadmin&command1=del&id=$id&database=$database>del</A></TD>
        </TR>
EOF
         }
         $cursor->finish;
         print <<"EOF";
      </TABLE>
    </TD>
  </TR>
</TABLE>
EOF
      } else {
         text("No notes match the search criteria");
      }

      # Checking SQL
      $count		= 0;
      $script_count	= 0;
      foreach $keyword(@keywords) {
         unless ($count) {
            $sql = "Select distinct name,id from ot_scripts where upper(name) like upper('\%$keyword\%')";
         } else {
            $sql .= " $andor upper(name) like upper('\%$keyword\%')";
         }
         $count++;
      } 
      logit("   SQL = $sql");
      $cursor = $mydbh->prepare($sql);
      $cursor->execute;
      while (($name,$id) = $cursor->fetchrow_array) {
         push @script_ids, $id;
         $script_count++;
         logit("  Name $name matches in table ot_scripts");
      }
      $count = 0;
      foreach $keyword(@keywords) {
         unless ($count) {
            $sql = "Select distinct id from ot_script_source where upper(text) like upper('\%$keyword\%')";
         } else {
            $sql .= " $andor upper(text) like upper('\%$keyword\%')";
         }
         $count++;
      }   
      logit("   SQL = $sql");
      $cursor = $mydbh->prepare($sql);
      $cursor->execute;
      while ($id = $cursor->fetchrow_array) {
         push @script_ids, $id;
         $script_count++;
         logit("  ID $id matches in table ot_script_source");
      }
      logit("         Script ID's: @script_ids.");
      $script_ids = "(" . join(",", @script_ids) . ")";
      logit ("Query will use these ID's: $script_ids");
      # Displaying SCRIPTS

      if ($script_count) {

         text("SQL scripts which match the search criteria");
         $sql = "
SELECT 
   DISTINCT ID,
   NAME,
   DESCRIPTION,
   TO_CHAR(CREATED,'Mon DD YYYY @ HH24:MI:SS'),
   EXECUTIONS
FROM OT_SCRIPTS WHERE ID IN $script_ids
   ORDER BY EXECUTIONS DESC
";

         print <<"EOF";
<TABLE BORDER =0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>
  <FORM METHOD=POST ACTION=$scriptname>
    <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
    <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Submit">
    <P>
    <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="MYORACLETOOL">
    <INPUT TYPE="HIDDEN" NAME="command" VALUE="scriptadmin">
    <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <TR>
    <TD WIDTH=100%>
      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Exec</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Edit</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Script</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Script Description</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Created</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'># Executions</TH>
        <TH BGCOLOR='$headingcolor' ALIGN=CENTER><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Del</TH>
EOF

         $cursor = $mydbh->prepare($sql);
         $cursor->execute;

         while (($id,$script,$desc,$created,$exec) = $cursor->fetchrow_array) {
            print <<"EOF";
        <TR>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><INPUT TYPE=CHECKBOX NAME=exec~$id></TD>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?object_type=MYORACLETOOL&command=scriptadmin&edit~$id&database=$database>Edit</A></TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$script</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$desc</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$created</TD>
          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$exec</TD>
          <TD ALIGN=CENTER BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A HREF=$scriptname?object_type=MYORACLETOOL&command=scriptadmin&del~$id&database=$database>Del</A></TD>
        </TR>
EOF
         }
         $cursor->finish;
         print <<"EOF";
      </TABLE>
    </TD>
  </TR>
  </FORM>
</TABLE>
EOF
      } else {
         text("No SQL scripts match the search criteria");
      }
      Footer();
   }
   logit("Exit subroutine myOracletool");
}

sub unique {

   my (@nonunique,@unique,%seen,$item);

   @nonunique = shift;

   %seen = ();
   foreach $item(@nonunique) {
      $seen{$item}++;
   }
   @unique = keys %seen;
   return(@unique);
}

sub parameterAdmin {

   logit("Enter subroutine parameterAdmin");

   my ($sql,$cursor,$parameter,$value,$text);

   text("</CENTER>Alter a modifiable system parameter. These parameters can be modified on the fly.");

   print <<"EOF";
<B>
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
  <INPUT TYPE="HIDDEN" NAME="arg" VALUE="changeparameter">
Alter system set 
  <SELECT SIZE=1 NAME=parameter>
EOF
   $sql = "$copyright
SELECT
   NAME,
   VALUE
FROM V\$PARAMETER
   WHERE ISSYS_MODIFIABLE != 'FALSE'
ORDER BY NAME
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   while (($parameter,$value) = $cursor->fetchrow) {
      print "    <OPTION>$parameter\n";
   }
   $cursor->finish;

   print <<"EOF";
  </SELECT>
   &nbsp;&nbsp;=&nbsp;&nbsp;
  <INPUT TYPE=TEXT MAXLENGTH=30 SIZE=30 NAME=value VALUE=$value>
  <P>
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Alter system">
</FORM>
<P><HR WIDTH=90%><P>
<CENTER>
EOF

   $sql = "
SELECT
   NAME,
   VALUE
FROM V\$PARAMETER
   WHERE ISSYS_MODIFIABLE != 'FALSE' 
ORDER BY NAME
";

   print "</CENTER>\n";
   $text = "Current values. Only parameters which may be modified while the system is up are displayed.";
   DisplayTable($sql,$text);

   logit("Exit subroutine parameterAdmin");

}

sub userAdmin {

   logit("Enter subroutine userAdmin");

   my ($sql,$cursor,$tablespace_name,$username,$profile,$count);

   text("</CENTER>Reset a user password.");

   print <<"EOF";
<B>
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
  <INPUT TYPE="HIDDEN" NAME="arg" VALUE="changepassword">
Alter user 
  <SELECT SIZE=1 NAME=username>
EOF
   $sql = "$copyright
SELECT
  USERNAME
FROM DBA_USERS
   ORDER BY USERNAME
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   while ($username = $cursor->fetchrow) {
      print "    <OPTION>$username\n";
   }
   $cursor->finish;

   print <<"EOF";
  </SELECT>
   &nbsp;&nbsp;identified by
  <INPUT TYPE=PASSWORD MAXLENGTH=30 SIZE=10 NAME=password>
  <P>
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Reset password">
</FORM>
<P><HR WIDTH=90%><P>
<CENTER>
EOF

   if ($oracle8) {

      logit("   Checking for locked accounts.");

      $sql = "
SELECT COUNT(*)
   FROM DBA_USERS
WHERE ACCOUNT_STATUS != 'OPEN'
";
      $count = recordCount($dbh,$sql);

      if ($count) {

         text("</CENTER>Unlock a user account.");

         print <<"EOF";
<B>
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
  <INPUT TYPE="HIDDEN" NAME="arg" VALUE="unlockuser">
Alter user
  <SELECT SIZE=1 NAME=username>
EOF
         $sql = "$copyright
SELECT
  USERNAME
FROM DBA_USERS
   WHERE ACCOUNT_STATUS != 'OPEN'
ORDER BY USERNAME
";

         $cursor = $dbh->prepare($sql);
         $cursor->execute;
         while ($username = $cursor->fetchrow_array) {
            print "    <OPTION>$username\n";
         }
         $cursor->finish;

         print <<"EOF";
  </SELECT>
   &nbsp;&nbsp;account unlock
  <P>
  <INPUT TYPE="SUBMIT" NAME="foobar" VALUE="Unlock account">
</FORM>
<P><HR WIDTH=90%><P>
<CENTER>
EOF
      } 
   }

   text("</CENTER>Create a user.");

   print <<"EOF";
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
  <INPUT TYPE="HIDDEN" NAME="arg" VALUE="createuser">
   Create user
  <INPUT TYPE=TEXT MAXLENGTH=30 SIZE=10 NAME=username>
   &nbsp;&nbsp;identified by
  <INPUT TYPE=PASSWORD MAXLENGTH=30 SIZE=10 NAME=password>
   &nbsp;&nbsp;default tablespace
EOF
   print <<"EOF";
  <SELECT SIZE=1 NAME=deftablespace>
EOF
   $sql = "$copyright
SELECT 
  TABLESPACE_NAME 
FROM DBA_TABLESPACES
   WHERE CONTENTS NOT IN ('TEMPORARY','UNDO')
ORDER BY TABLESPACE_NAME
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   while ($tablespace_name = $cursor->fetchrow) {
      print "    <OPTION>$tablespace_name\n";
   }
   $cursor->finish;

   print <<"EOF";
  </SELECT>
  <BR>temporary tablespace
  <SELECT SIZE=1 NAME=temptablespace>
EOF
   $sql = "$copyright
SELECT 
  TABLESPACE_NAME 
FROM DBA_TABLESPACES
   ORDER BY TABLESPACE_NAME
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   while ($tablespace_name = $cursor->fetchrow) {
      print "    <OPTION>$tablespace_name\n";
   }
   $cursor->finish;

   print <<"EOF";
  </SELECT>
  &nbsp;&nbsp;profile
  <SELECT SIZE=1 NAME=profile>
EOF
   $sql = "$copyright
SELECT 
  DISTINCT PROFILE
FROM DBA_PROFILES
   ORDER BY PROFILE
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   while ($profile = $cursor->fetchrow) {
      print "    <OPTION>$profile\n";
   }
   $cursor->finish;
   print <<"EOF";
  </SELECT>
  <P>
  <INPUT TYPE="SUBMIT" NAME="tablerows" VALUE="Create user">
</FORM>
<P><HR WIDTH=90%><P>
<CENTER>
EOF

   text("</CENTER>Create a user \"like\" another user.<BR>This will give the new user the same quotas, profile, default and temporary tablespace, roles, and system privileges as the selected user. It will not give the user any explicit object grants that the source user has been granted.");

   print <<"EOF";
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
  <INPUT TYPE="HIDDEN" NAME="arg" VALUE="copyuser">
   Create user
  <INPUT TYPE=TEXT MAXLENGTH=30 SIZE=10 NAME=username>
   &nbsp;&nbsp;identified by
  <INPUT TYPE=PASSWORD MAXLENGTH=30 SIZE=10 NAME=password>
  &nbsp;&nbsp;same as
  <SELECT SIZE=1 NAME=copyuser>
EOF

   $sql = "$copyright
SELECT
  USERNAME
FROM DBA_USERS
   ORDER BY USERNAME
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   while ($username = $cursor->fetchrow) {
      print "    <OPTION>$username\n";
   }
   $cursor->finish;

   print <<"EOF";
  </SELECT>
  <P>
  <INPUT TYPE="SUBMIT" NAME="tablerows" VALUE="Create user">
</FORM>
<P><HR WIDTH=90%><P>
<CENTER>
EOF

   text("</CENTER>Drop a user");

   print <<"EOF";
</CENTER>
<FORM METHOD=POST ACTION=$scriptname>
  <FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>
  <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
  <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="DBADMIN">
  <INPUT TYPE="HIDDEN" NAME="arg" VALUE="dropuser">
   Drop user
  <SELECT SIZE=1 NAME=username>
EOF

   $sql = "$copyright
SELECT
  USERNAME
FROM DBA_USERS
   ORDER BY USERNAME
";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;
   while ($username = $cursor->fetchrow) {
      print "    <OPTION>$username\n";
   }
   $cursor->finish;

   print <<"EOF";
  </SELECT>
  &nbsp;&nbsp;cascade
  <INPUT TYPE=CHECKBOX NAME=cascade VALUE=cascade>
  <P>
  <INPUT TYPE="SUBMIT" NAME="dropuser" VALUE="Drop user">
</FORM>
EOF

   logit("Exit subroutine userAdmin");

}

sub searchHelp {

   logit("Enter subroutine searchHelp");

   message("The search box can be used to find many types of objects, and in several ways. </CENTER><P>&nbsp;&nbsp;&nbsp;When you type in some text, it will search for schema names that match, tablespaces that match, and any type of standard object that matches. The search is done in \"LIKE\" fashion, which means that if you type in \"FOOBAR\", the search is done like so.. '%FOOBAR%', so you don't have to type in the whole object name, and you can add standard Oracle wildcard characters of your own, if you like.<P>
   &nbsp;&nbsp;&nbsp;You can narrow down the object search by fully qualifying the object name, like \"USERNAME.FOOBAR\".<P>
   &nbsp;&nbsp;&nbsp;If a numeric value is entered, the search will return any object which matches that OBJECT_ID.<P>
   &nbsp;&nbsp;&nbsp;If a comma is entered between two numeric values, like so.. \"12,3456\", then the first value is assumed to be a FILE#, and the second value is assumed to be a BLOCK_ID, and a search will be conducted for an object that resides within that file, and uses that BLOCK_ID. This is handy for finding objects while looking at an Oracle trace file.");

   logit("Exit subroutine searchHelp");

}

sub noInfo {

   logit("Enter subroutine showInfo");

   message("There is no additional information to display");

   logit("Exit subroutine showInfo");

}

sub parseConfig {

   my ($parameter,$eq,$val,$plugin);
   my $mytheme = $theme;
   my ($description,@themevars,$key,$themevarcount);

   open(CONFIG,"$config_file")
      or ErrorPage("Can't open config file $config_file. Reason: $!.");

   while (<CONFIG>) {

      next if ((/^$/) || (/^\s+$/) || (/^\s+#/) || (/^#/));

      chop;

      ($parameter,$val) = split(/=/);

      $parameter =~ s/^\s+//;
      $parameter =~ s/\s+$//;
      $val =~ s/^\s+//;
      $val =~ s/\s+$//;

      $parameter = uc($parameter);

      if ($parameter eq "EXPIRATION") {
         $expiration            = "$val";
         next;
      }
      if ($parameter eq "ORACLENAMES") {
         $oraclenames           = "Yep";
         next;
      }
      if ($parameter eq "DEBUG") {
         $debug                 = "Yep";
         next;
      }
      if ($parameter eq "LOGGING") {
         $logging               = "Yep";
         next;
      }
      if ($parameter eq "LOG") {
         $logfile               = "$val";
         next;
      }
      if ($parameter eq "ENCRYPTION_STRING") {
         $encryption_string     = "$val";
         next;
      }
      if ($parameter eq "ENCRYPTION_METHOD") {
         $encryption_method     = uc($val);
         next;
      }
      if ($parameter eq "UPLOAD_LIMIT") {
         $upload_limit     = $val;
         next;
      }
      if ($parameter eq "STATSPACK_SCHEMA") {
         $statspack_schema      = uc($val);
         next;
      } else {
         $statspack_schema      = "PERFSTAT";
      }

   # Add plugins

      if ($parameter eq "PLUGIN") {
         $plugin = $val;
         next;
      }
      if ($parameter eq "PROGRAM") {
         $plugins{$plugin} = $val;
         next;
      }

   # Add themes..

      if ($parameter eq "THEME") {
         $theme                 = "$val";
         $themevarcount++;
         next;
      }
      if ($parameter eq "DESCRIPTION") {
         $description           = "$val";
         $themevarcount++;
         next;
      }
      if ($parameter eq "BGCOLOR") {
         $bgcolor               = "$val";
         $themevarcount++;
         next;
      }
      if ($parameter eq "MENUIMAGE") {
         $menuimage             = "$val";
         $themevarcount++;
         next;
      }
      if ($parameter eq "BGIMAGE") {
         $bgimage               = "$val";
         $themevarcount++;
         next;
      }
      if ($parameter eq "FONTCOLOR") {
         $fontcolor             = "$val";
         $themevarcount++;
         next;
      }
      if ($parameter eq "HEADINGFONTCOLOR") {
         $headingfontcolor      = "$val";
         $themevarcount++;
         next;
      }
      if ($parameter eq "INFOCOLOR") {
         $infocolor             = "$val";
         $themevarcount++;
         next;
      }
      if ($parameter eq "LINKCOLOR") {
         $linkcolor             = "$val";
         $themevarcount++;
         next;
      }
      if ($parameter eq "FONT") {
         $font                  = "$val";
         $themevarcount++;
         next;
      }
      if ($parameter eq "HEADINGFONT") {
         $headingfont           = "$val";
         $themevarcount++;
         next;
      }
      if ($parameter eq "FONTSIZE") {
         $fontsize              = "$val";
         $themevarcount++;
         next;
      }
      if ($parameter eq "HEADINGCOLOR") {
         $headingcolor          = "$val";
         $themevarcount++;
         next;
      }
      if ($parameter eq "CELLCOLOR") {
         $cellcolor             = "$val";
         $themevarcount++;
         next;
      }
      if ($parameter eq "BORDERCOLOR") {
         $bordercolor           = "$val";
         $themevarcount++;
         next unless ($themevarcount == 15);
      }
      if (($themevarcount) && ($themevarcount == 15)) {
         push @{ $themes{$theme} }, $description;
         push @{ $themes{$theme} }, $bgcolor;
         push @{ $themes{$theme} }, $menuimage;
         push @{ $themes{$theme} }, $bgimage;
         push @{ $themes{$theme} }, $fontcolor;
         push @{ $themes{$theme} }, $headingfontcolor;
         push @{ $themes{$theme} }, $infocolor;
         push @{ $themes{$theme} }, $linkcolor;
         push @{ $themes{$theme} }, $font;
         push @{ $themes{$theme} }, $headingfont;
         push @{ $themes{$theme} }, $fontsize;
         push @{ $themes{$theme} }, $headingcolor;
         push @{ $themes{$theme} }, $cellcolor;
         push @{ $themes{$theme} }, $bordercolor;
         undef $themevarcount;
         next;
      }

   # If a parameter does not match a "hard coded" parameter
   # above, assume it is an environmental variable.

      $ENV{$parameter}  = $val;
   }
   close(CONFIG);

   if ((($debug) || ($logging)) && (! $logfile)) {
      undef $debug;
      undef $logging;
   }

   unless ($encryption_method) {
      logit("   ENCRYPTION_METHOD not set, defaulting to IDEA.");
      $encryption_method = "IDEA";
   }

   logit("Done reading config file ($config_file).");

# Check to be sure that a theme exists, in case it came
# from a cookie. If someone creates a personal theme and
# then installs a new version of the tool, their theme
# may not exist anymore, but it will still be in the
# OracletoolTheme cookie. Default, in this case.

   logit("MyTheme is set to $mytheme");

   foreach $key(keys %themes) {
      if ($mytheme eq $key) {
         $theme = $mytheme;
         last;
      } else {
         $theme = "Default";
      }
   }

   logit("Theme is set to $theme");

   foreach $key(keys %plugins) {
      logit("Plugin $key: Program $plugins{$key}");
   }

# Now set the variables for the selected theme.

   @themevars           = @{ $themes{$theme} };
   $description         = $themevars[0];
   $bgcolor             = $themevars[1];
   $menuimage           = $themevars[2];
   $bgimage             = $themevars[3];
   $fontcolor           = $themevars[4];
   $headingfontcolor    = $themevars[5];
   $infocolor           = $themevars[6];
   $linkcolor           = $themevars[7];
   $font                = $themevars[8];
   $headingfont         = $themevars[9];
   $fontsize            = $themevars[10];
   $headingcolor        = $themevars[11];
   $cellcolor           = $themevars[12];
   $bordercolor         = $themevars[13];

# Print environment to debug if enabled.

#   logit("Summary of ENV settings");
#   foreach $key(keys %ENV) {
#      logit("VAR: $key SETTING: $ENV{$key}");
#   }

}

sub dbConnect {

   logit("Enter subroutine dbConnect");

   my $dbh;
   my $database = shift;
   my $username = shift;
   my $password = shift;
   my $skiperrorcheck = shift || "";

   loginfo("   Log - Host: $ENV{'REMOTE_HOST'} IP: $ENV{'REMOTE_ADDR'} DB: $database Command: $object_type Theme: $theme") if $logging;

# Attempt to make connection to the database..

   my $data_source = "dbi:Oracle:$database";

   logit("   Datasource: $data_source");
   logit("   ORACLE_HOME $ENV{'ORACLE_HOME'}");
   logit("   TNS_ADMIN $ENV{'TNS_ADMIN'}");
   logit("   LD_LIBRARY_PATH $ENV{'LD_LIBRARY_PATH'}");

   logit("   Connecting as username [$username]...");
   if (uc($username) eq "SYS") {
      logit("   Connecting [$username] as SYSDBA");
      logit("   Executing DBI->connect($data_source,$username,$password,{ora_session_mode=> ORA_SYSDBA })");
      $dbh = DBI->connect($data_source,$username,$password,{ora_session_mode=> ORA_SYSDBA });
      logit("   Error: $DBI::errstr $!");
   } else {
      logit("   Not connecting [$username] as SYSDBA");
      $dbh = DBI->connect($data_source,$username,$password,{PrintError=>0});
   }

# If it fails, act on a couple of different Oracle errors.
# UNLESS $skipperrorcheck is set. This prevents a login screen
# from displaying when a login failure occurs. Instead, it
# will be handled by the parent subroutine.

   if ($skiperrorcheck) {
      logit("   Skipping error check upon request.");
   }

   unless ($skiperrorcheck) {

# Bring up the password screen for either of these errors.
# ORA-01017 - "Invalid username/password; logon denied."
# ORA-01004 - "Default username feature not supported; logon denied."
# ORA-01005 - "null password given; logon denied."

# Show an error message for these errors.
# ORA-12224 - "The connection request could not be completed because the listener is not running."
# ORA-01034 - "Oracle was not started up."
# ORA-01090 - "Shutdown in progress - connection is not permitted""
# ORA-12154 - "The service name specified is not defined correctly in the TNSNAMES.ORA file."
# ORA-12505 - "TNS:listener could not resolve SID given in connect descriptor."
# ORA-12545 - "TNS:name lookup failure."

      unless ($dbh) {
         logit("   Failed login with username \"$username\". $ENV{'REMOTE_HOST'} IP: $ENV{'REMOTE_ADDR'}");
         logit("      Error message is ~$DBI::errstr~");
         loginfo("   Failed login with username \"$username\". $ENV{'REMOTE_HOST'} IP: $ENV{'REMOTE_ADDR'}");
         if ( $DBI::errstr =~ /ORA-01017|ORA-1017|ORA-01004|ORA-01005/ ) {
            logit("   Login error is a recognized Oracle login error, sending them to the login screen.");
            EnterPasswd($database);
            exit;
         }
         logit("   Login error is not a recognized Oracle login error, checking for additional known errors.");
         if ( $DBI::errstr =~ /ORA-12224/ ) {
            ErrorPage ("You received an ORA-12224, which usually means the listener is down, or your connection definition in your tnsnames.ora file is incorrect. Check both of these things and try again.");
            exit;
         }
         if ( $DBI::errstr =~ /ORA-01034/ ) {
            ErrorPage ("You received an ORA-01034, which usually means the database is down. Check to be sure the database is up and try again.");
            exit;
         }
         if ( $DBI::errstr =~ /ORA-01090/ ) {
            ErrorPage ("You received an ORA-01090, which means the database is in the process of coming down.");
            exit;
         }
         if ( $DBI::errstr =~ /ORA-12154/ ) {
            ErrorPage ("You received an ORA-12154, which probably means you have a mistake in your TNSNAMES.ORA file for the database that you chose.");
            exit;
         }
         if ( $DBI::errstr =~ /ORA-12505/ ) {
            ErrorPage ("You received an ORA-12505, which probably means you have a mistake in your TNSNAMES.ORA file for the database that you chose, or the database you are trying to connect to is not defined to the listener that is running on that node.");
            exit;
         }
         if ( $DBI::errstr =~ /ORA-12545/ ) {
            ErrorPage ("You received an ORA-12545, which probably means you have a mistake in your TNSNAMES.ORA file for the database that you chose. (Possibly the node name).");
            exit;
         }
         logit("   Unable to connect to Oracle ($DBI::errstr)");
         ErrorPage ("Unable to connect to Oracle ($DBI::errstr)\n");
         exit;
      }
      logit("   Got successful connection");
      logit("Exit subroutine dbConnect");
   }
   logit("Returning");
   return ($dbh);

}

sub DisplayTable {

   logit("Enter subroutine DisplayTable");

# Usage:  DisplayTable ($sql,$text,$link,$infotext,$rows,$dbh);

# This sub is for formatting the output of a SQL query. The
# output will have the column headings in bold with the data
# in a HTML table.
# The first arg is the SQL you want to execute.
# The second arg (text) is for optionally putting a text description
# of the outputted data above the table.
# The third argument is to optionally make the table output
# a hyperlink. the hyperlink will use the data in the first column
# as an argument to whatever the link is pointing to.
# The fourth argument is the text that you want to display if
# no rows are returned from the query.
# The fifth argument is for optionally specifying a set number of
# rows to return.
# The sixth argument is to optionally specify a database handle other
# than the default connection. This was added for MyOracletool.

   my $sql      = shift || "";
   my $text     = shift || "";
   my $link     = shift || "";
   my $infotext = shift || "";
   my $rows     = shift || "";
   my $dbh      = shift || $dbh;
   my $count    = 0;

   logit("SQL: $sql");
#   logit("Text: $text");
#   logit("link: $link");
#   logit("infotext: $infotext");
#   logit("rows: $rows");
#   logit("count: $count");
#   logit("dbh: $dbh");

   logit("   Link passed = $link") if $link;
# Change spaces to +'s on links passed.
   $link =~ s/ /+/g if $link;

   $dbh->{LongReadLen} = 2048;
   $dbh->{LongTruncOk} = 1;

   $infotext = "<FONT COLOR=\"$infocolor\">$infotext</FONT>" if $infotext;

   my ($cursor,@row,$numfields,$field,$name,$arg);

   if ( $link eq "" ) {
      undef $link;
   } else {
      $link =~ tr/ /+/;
   }

   $cursor = $dbh->prepare($sql) or return($DBI::errstr);
   $cursor->execute or return($DBI::errstr);

   while (@row = $cursor->fetchrow_array) {
      $count++;
   }
   logit("   Rows returned: $count");
   $cursor->finish or return("$DBI::errstr");
   if ($count != 0) {
      $count = 0;
      print "<P><B>$text</B></P>\n" if defined $text;
      print "<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>\n";
      print "<TR><TD WIDTH=100%>\n";
      print "<TABLE BORDER=0 cellpadding=2 cellspacing=1>\n";
      $cursor = $dbh->prepare($sql) or return($DBI::errstr);
      $cursor->execute or return($DBI::errstr);
      $numfields = $cursor->{NUM_OF_FIELDS};

      for ($field=0; $field < $numfields; $field++) {
         $name = $cursor->{NAME}->[$field];
         print "<TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>$name</TH>";
      }
      print "\n";
      while (@row = $cursor->fetchrow_array) {
         $count++;
         print "<TR ALIGN=LEFT>";
         for (my $field=0; $field < $numfields; $field++) {
            if ($field == 0) {
# Change spaces to +'s, and escape all unsafe characters
               $_ = $row[$field];
               s/ /+/g;
               s/#/\%23/g;
               s/</\%3C/g;
               s/>/\%3E/g;
               s/{/\%7B/g;
               s/\|/\%7C/g;
               s/}/\%7D/g;
               s/\\/\%5C/g;
               s/\^/\%5E/g;
               $arg = $_;
            }
            print "<TD VALIGN=TOP BGCOLOR='$cellcolor'";
            if ((defined $row[$field]) && ($row[$field] ne "")) {
               print " ALIGN=RIGHT" if ($row[$field] =~ /^\s*\.?\d/);
# Change spaces to real HTML spaces and fix HTML characters.
               $row[$field] =~ s/&/&amp;/g;
               $row[$field] =~ s/\s/&nbsp;/g;
               $row[$field] =~ s/\"/&quot;/g;
               $row[$field] =~ s/>/&gt;/g;
               $row[$field] =~ s/</&lt;/g;

               if (($link) && ($field == 0)) {
                  print "><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A href=$link&arg=$arg>$row[$field]</A></TD>\n";
               } else {
                  print "><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$row[$field]</TD>\n";
               }
            } else {
               print ">&nbsp;</TD>\n";
            }
         }
         print "</TR>\n";
         if ($rows) {
            last if ($count > $rows);
         }
      }
      print "</TABLE></TD></TR>\n";
      print "</TABLE>\n";
      $cursor->finish or return("$DBI::errstr");
   } else {
      print "<P><B>$infotext</B></P>\n" if ( defined $infotext );
   }

   logit("Exit subroutine DisplayTable");

   return($count);
}

sub DisplayColTable {

   logit("Enter subroutine DisplayColTable");

# Usage: DisplayColTable ($sql,$text,$link,$infotext,$cols);

# This sub is for displaying a table of 'n' columns
# wide from a query that returns a single column of
# data.
# The first arg is the SQL you want to execute.
# The second arg (text) is for optionally putting a text description
# of the outputted data above the table.
# The third argument is to optionally make the table output
# a hyperlink. the hyperlink will use the data in the first column
# as an argument to whatever the link is pointing to.
# The fourth argument is the text that you want to display if
# no rows are returned from the query.
# The fifth argument is the number of columns wide you want the table
# to be.
# The sixth argument is if you want a checkbox beside each entry
# The seventh argument is the target (read by Director()) to go to.
# The eight (Geez!) argument is to set a value to the hidden param "command"

   my $sql              = shift;
   my $text             = shift;
   my $link             = shift;
   my $infotext         = shift;
   my $cols             = shift;
   my $checkbox         = shift;
   my $target           = shift;
   my $submittext       = shift;
   my $command          = shift;
   my $counter  = 0;

   my ($cursor,$row,$i,@row,$count,$skip,$arg);

   logit("SQL: $sql");

   $dbh->{LongReadLen} = 2048;

   $infotext = "<FONT COLOR=\"$infocolor\">$infotext</FONT>";

   $cursor = $dbh->prepare($sql);
   $cursor->execute;

   $count = 0;
   while (@row = $cursor->fetchrow_array) {
      $count++;
   }
   if ($count <= $cols) {
      $cols = $count;
   }
   $cursor->finish;
   if ($count != 0) {
      print "<P><B>$text</B></P>\n" if defined $text;
      print "<TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>\n";
      if ($checkbox) {
         print <<"EOF";
  <FORM METHOD=POST ACTION=$scriptname>
    <INPUT TYPE="HIDDEN" NAME="database" VALUE="$database">
    <INPUT TYPE="HIDDEN" NAME="object_type" VALUE="$target">
    <INPUT TYPE="HIDDEN" NAME="command" VALUE="$command">
EOF
      }
      print "  <TR>\n";
      print "    <TD WIDTH=100%>\n";
      print "      <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>\n";
      $cursor = $dbh->prepare($sql) or return($DBI::errstr);
      $cursor->execute or return($DBI::errstr);
      while ($row = $cursor->fetchrow_array) {
         $arg = $row;
         $arg =~ s/ /+/;
         print "        <TR ALIGN=CENTER>" if $counter == 0;
         if ($link) {
            print "          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><A href=$link&arg=$arg>$row</A></TD>\n";
         } else {
            if ($checkbox) {
               print "          <TD ALIGN=LEFT BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><INPUT TYPE=CHECKBOX NAME=checked~$row>&nbsp;$row</TD>\n";
            } else {
               print "          <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'>$row</TD>\n";
            }
         }
         $counter++;
         print "        </TR>" if $counter == 0;
         $skip = "";
         if ($counter == $cols) {
            $counter = 0;
            $skip = "Y";
         }
      }
      if ((! $skip) && ($counter < $cols)) {
         for ($i = $counter; $i < $cols; $i++) {
            print "          <TD BGCOLOR='$cellcolor'>&nbsp;</TD>\n";
         }
      }
      print "      </TABLE>\n";
      print "    </TD>\n";
      print "  </TR>\n";
      if ($checkbox) {
      print <<"EOF";
<INPUT TYPE=SUBMIT VALUE="$submittext">
</FORM>
EOF
      }
      print "</TABLE>\n";

      $cursor->finish;
   } else {
      print "<P><B>$infotext</B></P>\n" if ( defined $infotext );
   }

   logit("Exit subroutine DisplayColTable");

   if ($DBI::errstr) {
      return($DBI::errstr);
   } else {
      return($count);
   }
}

sub DisplayPiecedData {

   logit("Enter subroutine DisplayPiecedData");

# Usage:   DisplayPiecedData ($sql,$text,$link)

# This is for formatting the output of a SQL query. The
# output will have the column headings in bold with the data
# in a HTML table. This sub should be used for data retrieved
# from tables which have the data in pieces such as dba_source,
# and v$sql.
# The first arg is the SQL you want to execute.
# The second arg (text) is for optionally putting a text description
# of the outputted data above the table.
# The third argument is to optionally make the table output
# a hyperlink. the hyperlink will use the data in the first column
# as an argument to whatever the link is pointing to.

   my $sql      = shift || "";
   my $text     = shift || "";
   my $link     = shift || "";
   my $numbers  = shift || "";
   my $count = 0;

   my ($cursor,@row,$field,$name,$arg,$row,$data);
   my (@lines,$line,$linecounter);

   if ( $link eq "" ) {
      undef $link;
   } else {
      $link =~ tr/ /+/;
   }
   $dbh->{LongReadLen} = 10240;
   $dbh->{LongTruncOk} = 1;

   $data= "";
   $cursor = $dbh->prepare($sql) or ErrorPage ("$DBI::errstr");
   $cursor->execute or ErrorPage ("$DBI::errstr");
   while (@row = $cursor->fetchrow_array) {
      $count++;
   }
   $cursor->finish or ErrorPage ("$DBI::errstr");
   if ($count != 0) {
      $cursor = $dbh->prepare($sql) or ErrorPage ("$DBI::errstr");
      $cursor->execute or ErrorPage ("$DBI::errstr");

      while ($_ = $cursor->fetchrow_array) {
            s/</&lt;/g;
            s/>/&gt;/g;
            $row = $_;
            $data = "$data$row";
      }
      print "<P><B>$text</B></P>\n" if defined $text;
      print "<TABLE BORDER=0>\n";
      print "  <TR>\n";
      print "    <TD>\n";
      print "      <TABLE BORDER=0 BGCOLOR='$bordercolor' CELLPADDING=1 CELLSPACING=0>\n";
      print "        <TR>\n";
      print "          <TD WIDTH=100%>\n";
      print "            <TABLE BORDER=0 CELLPADDING=2 CELLSPACING=1>\n";
      print "              <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Recreate text</TH>\n";
      print "              <TH BGCOLOR='$headingcolor'><FONT COLOR='$headingfontcolor' SIZE='$fontsize' FACE='$headingfont'>Debug text</TH>\n";
      print "              <TR>\n";
      print "                <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><PRE>$data</PRE></TD>" if ! defined $link;
      print "                <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><PRE><A href=$link&arg=$arg>$data</A></PRE></TD>" if defined $link;
      @lines = split /\n/, $data;
      $linecounter = 0;
      print "                <TD BGCOLOR='$cellcolor'><FONT COLOR='$fontcolor' SIZE='$fontsize' FACE='$font'><PRE>\n\n";
      foreach $line (@lines) {
         $linecounter++;
         print "<FONT COLOR=$linkcolor><$linecounter></FONT>  $line<BR>" if ! defined $link;
         print "<A href=$link&arg=$arg><FONT COLOR=$linkcolor><$linecounter></FONT> $line</A><BR>" if defined $link;
      }
      print "                </PRE>\n";
      print "                </TD>\n";
      print "              </TR>";
      print "            </TABLE>\n";
      print "          </TD>\n";
      print "        </TR>\n";
      print "      </TABLE>\n";
      print "    </TD>\n";
      print "  </TR>\n";
      print "</TABLE>\n";
      $cursor->finish or ErrorPage ("$DBI::errstr");
   }

   logit("Exit subroutine DisplayPiecedData");

}

sub Header {

# Usage: Header ($title,$heading,$font,$fontsize,$fontcolor,$bgcolor);

   logit("Enter subroutine Header");

   my ($title,$heading,$font,$fontsize,$fontcolor,$bgcolor,$headertype);
   my ($refreshrate,$url,$arg,$sortfield,$bgline,$path,$cookie,$filename);
   my ($param);

# Creates a HTML header with title

   $title      = shift || "";
   $heading    = shift || "";
   $font       = shift || "";
   $fontsize   = shift || "";
   $fontcolor  = shift || "";
   $bgcolor    = shift || "";

   $headertype  = $query->param('headertype') || "text/html";
   $refreshrate = $query->param('refreshrate') || "";
   $sortfield   = $query->param('sortfield') || "";

   $url  = $scriptname;
   $url .= "?database=$database" if $database;
   $url .= "&user=$user" if $user;
   $url .= "&schema=$schema" if $schema;
   $url .= "&object_type=$object_type" if $object_type;
   $url .= "&arg=$arg" if $arg;
   $url .= "&refreshrate=$refreshrate" if $refreshrate;
   $url .= "&sortfield=$sortfield" if $sortfield;

   # Save this database connection in a cookie to retrieve as the most recent.
   $path   = dirname($scriptname);
   logit ("   Path is $path");
   $cookie = cookie(-name=>"OracletoolRecent",-value=>"$database",-expires=>"+10y");

   if ($headertype ne "text/html") {
      binmode(STDOUT);
      $filename = $query->param('filename') || undef $filename;
      $filename =~ s/xx===xx/ /g;
      $param    = $query->param('command1') || undef $param;
      logit("   Putting Content-Disposition into header");
      logit("   Content-Disposition:attachment;filename=$filename");
      print "Content-Disposition:attachment;filename=$filename\n";
   } else {
      $headertype="text/html";
   }
   print header(-type => $headertype,-cookie=>$cookie);

   if ($headertype eq "text/html") {
      $bgline = "<BODY BGCOLOR=$bgcolor LINK=$linkcolor ALINK=$linkcolor VLINK=$linkcolor>\n";
      if ($bgimage) {
         if ((-e "$ENV{'DOCUMENT_ROOT'}/$bgimage") && (-r "$ENV{'DOCUMENT_ROOT'}/$bgimage")) {
            logit("   Background image is $ENV{'DOCUMENT_ROOT'}/$bgimage and is readable");
            $bgline = "<BODY BACKGROUND=$bgimage LINK=$linkcolor ALINK=$linkcolor VLINK=$linkcolor>\n";
         }
      }
#   } else {
#      $filename = $query->param('value');
#      if ($filename) {
#         logit("   Putting attachment filename $filename in the header");
#         print "Content-Disposition: attachment; filename=$filename";
#      }
   }

   if ($headertype eq "text/html") {

      print << "EOF";
<HTML>
<HEAD>
EOF
# Set a refresh rate for the page if desired
      if ($refreshrate) {
         logit("   Refresh rate of $refreshrate set. URL = $url");
         print "<META HTTP-EQUIV=\"Refresh\" Content=\"$refreshrate;URL=$url\">\n";
      }
      print << "EOF";
<META HTTP-EQUIV="pragma" CONTENT="nocache">
<STYLE TYPE="text/css">
        <!-- A{text-decoration: none;} A:link{color: $linkcolor;}A:visited{color: $linkcolor;} -->
</STYLE>
<TITLE>$title</TITLE>
</HEAD>
$bgline
EOF
print << "EOF";
<FONT FACE="$font" SIZE="$fontsize" COLOR="$fontcolor">
<BR><BR>
<CENTER>
EOF

# The following was added to send a message to people I noticed were
#  trying to break into my demo database.

      my (@forbidden,$forbidden_message,$forbidden_ip);

      @forbidden = ("");
      $forbidden_message = "Hello, $ENV{'REMOTE_ADDR'}. You have been denied access until you start being more helpful.";

      foreach $forbidden_ip(@forbidden) {
         if ($ENV{'REMOTE_ADDR'} eq $forbidden_ip) {
            message($forbidden_message);
            exit;
         }
      }
      if ( $heading ne "" ) {
         print "$heading";
      }
   }

   logit("Exit subroutine Header");

}

sub Footer {

   logit("Enter subroutine Footer");

# Usage: Footer();

# Creates a HTML footer that refers back

print <<"EOF";
</BODY>
</HTML>
EOF

   logit("Exit subroutine Footer and Oracletool. Bye!");

   exit;

}

sub loginfo {

   my $text = shift;

   if ($logging) {
      open (LOG,">>$logfile") or die "Oracletool error! Cannot open log file \"$logfile\"! You need to disable logging or choose a filename that you have permission to write to.";
      print LOG "$text\n";
      close (LOG);
   }
}

sub logit {

   my $text = shift;

   if ($debug) {
      open (LOG,">>$logfile") or die "Oracletool error! Cannot open log file \"$logfile\"! You need to disable logging or choose a filename that you have permission to write to.";
      print LOG "$text\n";
      close (LOG);
   }
}

sub GetTNS {

   logit("Enter subroutine GetTNS");

# Usage: @tns_entries = GetTNS();
# If you have ever wondered why Russia was first in space, check out the hacks below!
# Many thanks to Dima Dorofeev.

# Returns the database connection strings defined in the tnsnames.ora.
# Also removes duplicates and sorts alphabetically. Duplicates can show
# up because the DBI->data_sources checks both the tnsnames.ora file
# and the oratab file. There are several possibilities here, I'm waiting
# to see if there are any complaints before I remove the others.

# 1  my %hash =  map { (split(':'))[-1] , undef } DBI->data_sources('Oracle');
# 2  my %hash = map { /\:(\w[\w-]*)(?:\.world){0,1}$/i , undef } DBI->data_sources('Oracle');
#   delete($hash{""});
# 3  my %hash = map { /\:([\.\w]+)(?:\.world){0,1}$/i , undef } DBI->data_sources('Oracle');
   my %hash = map { (split(/\.world/i,(split(':'))[-1]))[0] , undef } DBI->data_sources('Oracle')
      or logit("   Error getting datasources ($!)");
   my @data_sources = sort keys %hash;

   logit("   Data sources (@data_sources)");
   logit("Exit subroutine GetTNS");

   return sort keys %hash;

}

sub Director {

   logit("Enter subroutine Director");

# Put the if's here for reporting on the different types of objects.

# Display search box help screen.
   if ($object_type eq "SEARCHHELP")			{searchHelp();}

# System modifiable parameter admin.
   if ($object_type eq "PARAMETERADMIN")		{parameterAdmin();}

# Multi threaded server info
   if ($object_type eq "MTSINFO")			{mtsInfo();}

# My Oracletool admin.
   if ($object_type eq "MYORACLETOOL")			{myOracletool();}

# My Oracletool creation.
   if ($object_type eq "MYORACLETOOLCREATE")		{myOracletoolCreate();}

# Show audit trail records for deletion.
   if ($object_type eq "VALIDATEINDEX")			{validateIndex();}

# Show audit trail records for deletion.
   if ($object_type eq "AUDITLIST")			{auditList();}

# Show rollbacks for administration.
   if ($object_type eq "RBSLIST")			{rbsList();}

# Show Recovery Manager controlfile information.
   if ($object_type eq "RMANBACKUPS")			{rmanBackups();}

# Show Recovery Manager catalog information.
   if ($object_type eq "RMANCATALOGQUERY")		{rmanCatalogQuery();}

# Monitor a Recovery Manager backup.
   if ($object_type eq "RMANMONITOR")			{rmanMonitor();}

# Show audit trail records.
   if ($object_type eq "SHOWAUDITTRAIL")		{showAuditTrail();}

# Choose auditing options.
   if ($object_type eq "ENTERAUDITS")			{enterAudits();}

# Show a schemas invalid objects
   if ($object_type eq "SHOWINVALIDOBJECTS")		{showInvalidObjects();}

# Show SQL in V$SQL for a user.
   if ($object_type eq "SQLAREALISTBYUSER")		{sqlAreaListByUser();}

# Show list of users with SQL in V$SQL.
   if ($object_type eq "SQLAREALIST")			{sqlAreaList();}

# Object administration.
   if ($object_type eq "OBJECTADMIN")			{objectAdmin();}

# Rollback / transaction information

   if ($object_type eq "ROLLBACKMENU")                  {rollbackMenu();}

# StatsPack information menu.
   if ($object_type eq "STATSPACKMENU")			{statsPackMenu();}

# StatsPack snapshot.
   if ($object_type eq "STATSPACKADMIN")		{statsPackAdmin();}

# Backup (RMAN) information menu.
   if ($object_type eq "BACKUPMENU")			{backupMenu();}

# Auditing administration menu.
   if ($object_type eq "PERFMENU")			{perfMenu();}

# Auditing administration menu.
   if ($object_type eq "AUDITMENU")			{auditMenu();}

# Session administration menu.
   if ($object_type eq "SESSIONMENU")			{sessionMenu();}

# Preferences menu.
   if ($object_type eq "PREFMENU")			{prefMenu();}

# Auditing administration.
   if ($object_type eq "AUDITADMIN")			{auditAdmin();}

# Kill multiple sessions. Die die die!!! :)
   if ($object_type eq "SESSIONLIST")			{sessionList();}

# Execute user administration commands
   if ($object_type eq "DBADMIN")			{dbAdmin();}

# Create a user
   if ($object_type eq "USERADMIN")		{userAdmin();}

# Report for a specific something
   if ($object_type eq "JAVA CLASS" || $object_type eq "JAVA RESOURCE")	   {noInfo();}

# Display all themes for choosing.
   if ($object_type eq "SHOWTHEMES")		{showThemes();}

# Display menu for choosing typical DBA type tasks.
   if ($object_type eq "TASKMENU")         {taskMenu();}

# Display tool properties.
   if ($object_type eq "SHOWPROPS")        {showProps();}

# Set a default theme that the user has chosen. Store in a cookie.
#   if ($object_type eq "SETTHEME")        {setTheme();}

# Report for a specific queue
   if ($object_type eq "QUEUE")	           {showQueue();}

# Report for a specific operator
   if ($object_type eq "OPERATOR")	   {showOperator();}

# Report for a specific library
   if ($object_type eq "LIBRARY")	   {showLibrary();}

# Report for a specific cluster
   if ($object_type eq "CLUSTER")	   {showCluster();}

# Report for a specific indextype
   if ($object_type eq "INDEXTYPE")	   {showIndextype();}

# Report for a specific table.
   if ($object_type eq "TABLE")            {showTable();}

# Report for a specific table partition
   if ($object_type eq "TABLE PARTITION")  {showTablePart();}

# Report for a specific view.
   if ($object_type eq "VIEW")             {showView();}

# Report for a specific trigger.
   if ($object_type eq "TRIGGER")          {showTrigger();}

# Report for a specific database link.
   if ($object_type eq "DATABASE LINK")    {showDBlink();}

# Report for a specific function.
   if ($object_type eq "FUNCTION")         {showSource();}

# Report for a specific package body.
   if ($object_type eq "PACKAGE BODY")     {showSource();}

# Report for a specific package.
   if ($object_type eq "PACKAGE")          {showSource();}

# Report for a specific procedure.
   if ($object_type eq "PROCEDURE")        {showSource();}

# Report for a specific sequence.
   if ($object_type eq "SEQUENCE")         {showSequence();}

# Report for a specific index.
   if ($object_type eq "INDEX")            {showIndex();}

# Report for a specific index partition.
   if ($object_type eq "INDEX PARTITION")  {showIndexPart();}

# Report for a specific synonym.
   if ($object_type eq "SYNONYM")          {showSynonym();}

# Report on all privileges granted to a specific user.
   if ($object_type eq "GRANTSTO")         {showGrantsto();}

# Report on all privileges granted to a specific role.
   if ($object_type eq "ROLES")            {showRoles();}

# Report on all privileges granted from a specific user.
   if ($object_type eq "GRANTSFROM")       {showGrantsfrom();}

# This is what I call the "toplevel" page. Lists all users in database.
   if ($object_type eq "LISTUSERS")        {showUsers();}

# This is where you go after selecting a user. Lists general info,
# buttons for grants, and a list of object types owned by the user.
   if ($object_type eq "USERINFO")         {userInfo();}

# This will bring back a table of objects that are of the type that
# the user clicked on.
   if ($object_type eq "LISTOBJECTS")      {showObjects();}

# List all of the tablespaces in the database.
   if ($object_type eq "TABLESPACES")      {showTablespaces();}

# Report on information about a specific tablespace.
   if ($object_type eq "TSINFO")           {showTSinfo();}

# Display all objects within a specific tablespace.
   if ($object_type eq "SHOWTSOBJECTS")    {showTSobjects();}

# Show a clickable list of all datafiles in the database
   if ($object_type eq "DATAFILES")        {showDBfiles();}

# Show information abaout a particular datafile
   if ($object_type eq "DATAFILE")         {showFile();}

# Show all instance parameters from V$PARAMETER in a table
   if ($object_type eq "PARAMETERS")       {showParameters();}

# Show information about redologs, including a graph
   if ($object_type eq "REDOLOGS")         {showRedo();}

# Show information about all sessions in the instance, or
# for a particular user, if $user is set
   if ($object_type eq "SESSIONS")         {showSessions($user);}

# Show detailed information about a session
   if ($object_type eq "SESSIONINFO")      {sessionInfo();}

# Show instance session summary with refresh, sortable.
   if ($object_type eq "TOPSESSIONS")      {topSessions();}

# Show global session wait information.
   if ($object_type eq "SESSIONWAIT")      {sessionWait();}

# Show global session wait information.
   if ($object_type eq "SESSIONWAITBYEVENT")      {sessionWaitByEvent();}

# Display "n" rows 
   if ($object_type eq "TABLEROWS")        {showRows("$rowdisplay");}

# Display information about a constraint
   if ($object_type eq "CONSTRAINT")       {showConstraint();}

# Show a clickable list of all rollback segments in the database
   if ($object_type eq "SHOWROLLBACKS")     {showRollbacks();}

# Show a list of all active / rolling back transactions in the database
   if ($object_type eq "SHOWTRANSACTIONS")  {showTransactions();}

# Show information about a particular rollback segment
   if ($object_type eq "ROLLBACK")         {showRollback();}

# Check the instance for contending and non-contending locks
   if ($object_type eq "CONTENTION")       {showContention();}

# Show a table graph of datafiles with allocation
   if ($object_type eq "FILEGRAPH")        {showFilegraph();}

# Show a table graph of tablespaces with allocation
   if ($object_type eq "TSGRAPH")          {showTSgraph();}

# Show statistics for a particular file
   if ($object_type eq "TSFILEGRAPH")      {showTSfilegraph();}

# Show statistics for a selected session
   if ($object_type eq "SESSIONSTATS")     {showSessionstats();}

# Break down a user's object usage by object type and tablespace
   if ($object_type eq "OBJECTREPORT")     {objectReport();}

# Report of space usage by user
   if ($object_type eq "USERSPACEREPORT")     {userSpaceReport();}

# Report of space usage by tablespace / user
   if ($object_type eq "TSSPACEREPORT")     {tsSpaceReport();}

# Report of datafile fragmentation
   if ($object_type eq "FILEFRAGREPORT")   {fileFragReport();}

# Enter number of extents for extent report
   if ($object_type eq "ENTEREXTENTREPORT")   {enterExtentReport();}

# Run an extent report
   if ($object_type eq "EXTENTREPORT")        {extentReport();}

# Show OPS related information
   if ($object_type eq "OPSMENU")             {opsMenu();}

# Show OPS related information
   if ($object_type eq "OPSINFO")             {opsInfo();}

# Search for objects by object name or object ID
   if ($object_type eq "OBJECTSEARCH")     {objectSearch();}

# Show the privileges granted to users for a particular object
   if ($object_type eq "OBJECTGRANTS")     {showObjectGrants();}

# Show memory and performance related data
   if ($object_type eq "PERFORMANCE")      {showPerformance();}

# Bring up the explain plan screen
   if ($object_type eq "EXPLAINSCREEN")    {explainScreen();}

# Bring up a box for a user to run SQL in an explain plan as a
# user other than the user logged in to Oracletool. This is 
# executed from the session information screens.
   if ($object_type eq "EXPLAINPLAN")      {enterExplainPlan();}

# Run the explain plan
   if ($object_type eq "RUNEXPLAINPLAN")   {runExplainPlan();}

# SQL-Worksheet
   if ($object_type eq "WORKSHEET")        {enterWorksheet();}

# Run the SQL entered on the worksheet
   if ($object_type eq "RUNSQL")	   {runSQL($dbh);}

# Show settings for a profile
   if ($object_type eq "PROFILE")          {showProfile();}

# Show roles, profiles, and users with the DBA role
   if ($object_type eq "SECURITY")         {showSecurity();}

# Show auditing information
   if ($object_type eq "AUDITING")         {showAllAuditing();}

# Show archiving information
   if ($object_type eq "ARCHIVING")        {showArchiving();}

# Show controlfile information
   if ($object_type eq "CONTROLFILES")     {showControlfiles();}

# Show Replication information (Master)
   if ($object_type eq "REPMASTER")        {showRepmaster();}

# Show advanced replication groups 
   if ($object_type eq "ADVREP")           {showAdvRepGroups();}

# Show group information, advanced replication
   if ($object_type eq "ADVREPGROUP")      {showAdvRepGroup();}

# Show Refresh groups
   if ($object_type eq "REFRESHGROUPS")    {showRefreshgroups();}

# Show Refresh group children.
   if ($object_type eq "REFRESHINFO")      {showRefreshinfo();}

# Show info for a particular snapshot 
   if ($object_type eq "SNAPINFO")         {showSnapinfo();}

# Generate all DDL to recreate a tablespace
   if ($object_type eq "TSDDL")		    {tsDDL();}

# Generate all DDL to recreate an object and its dependencies
   if ($object_type eq "OBJECTDDL")         {objectDDL();}

# Generate all DDL to recreate a user and its dependencies
   if ($object_type eq "USERDDL")          {userDDL();}

# Show a fragmentation map of a datafile or tablespace
   if ($object_type eq "FRAGMAP")      	   {fragMap();}

# Show a fragmentation list of a datafile or tablespace
   if ($object_type eq "FRAGLIST")         {fragList();}

# Show a fragmentation map of an object
   if ($object_type eq "OBJECTFRAGMAP")	   {objectFragMap();}

# Trace a session
   if ($object_type eq "TRACESESSION")      {traceSession();}

# Kill a session
   if ($object_type eq "KILLSESSION")      {killSession();}

# Show a fragmentation map of a datafile
   if ($object_type eq "DBFILE_BLOCK")     {dbfileBlock();}

# Show some info about things that have recently changed in the database.
   if ($object_type eq "RECENTEVENTS")      {recentEvents();}

# DBMS_JOB interface.
   if ($object_type eq "JOBSCHEDULER")		{jobScheduler();}

# Multi instance healthcheck.
   if ($object_type eq "HEALTHCHECK")		{healthCheck();}

# Multi instance healthcheck menu.
   if ($object_type eq "HEALTHCHECKMENU")	{healthCheckMenu();}

# Peoplesoft menu items.
   if ($object_type eq "PSOFTMENU")		{psoftMenu();}

# Look for strings of SQL in V$SQLAREA.
   if ($object_type eq "SQLAREACOUNT")		{SQLareaCount();}

# Show ASM info
   if ($object_type eq "ASM")			{ASMinfo();}

# Show ASM info
   if ($object_type eq "ASMDISKS")		{ASMdisks();}

# Show Bind variable info
   if ($object_type eq "BINDVARS")		{bindVars();}

# Show explain plan (builtin)
   if ($object_type eq "QUICKEXPLAIN")		{quickExplain();}

# Show datapump active job information
   if ($object_type eq "DATAPUMPJOBS")		{datapumpJobs();}

# Show a particular datapump job
   if ($object_type eq "DATAPUMPJOB")		{datapumpJob();}

# Show a particular datapump job
   if ($object_type eq "TEMP_TS_GROUPS")	{tempTsGroups();}

# Show detailed info about a SQL statement
   if ($object_type eq "SQLINFO")		{sqlInfo();}

# Show info about flashback
   if ($object_type eq "FLASHBACKINFO")		{flashbackInfo();}

   logit("Exit subroutine Director");

}
