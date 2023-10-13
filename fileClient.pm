#!/usr/bin/perl
#-------------------------------------------------------------------------
# the main application object
#-------------------------------------------------------------------------
# Currently uses 'buddy' standard data dir to hold the fileClient.prefs file

# PRH - need to implement prefsDlg
# PRH - I think buddy prefs go in fileClient.prefs (it's all one big thing?)

package apps::fileClient::AppFrame;
use strict;
use warnings;
use threads;
use threads::shared;
use Wx qw(:everything);
use Wx::Event qw(EVT_MENU_RANGE);
use Pub::Utils;
use Pub::WX::Frame;
use apps::fileClient::Resources;
use apps::fileClient::Window;
use apps::fileClient::Prefs;
use apps::fileClient::PrefsDialog;
use apps::fileClient::ConnectDialog;
use base qw(Pub::WX::Frame);

my $dbg_app = 0;




sub new
{
	my ($class, $parent) = @_;

	warning($dbg_app,-1,"FILE CLIENT STARTED WITH PID($$)");

	return if !initPrefs();
		# we get the prefs first cuz there are preferences
		# related to how we want to restore the app

	# if any command line arguments are passed,
	# or the restore_startup pref is not set,
	# we merely restore the main window rectangle.
	#
	# otherwise, the Frame base class witll restore
	# the windows, and later we will NOT do the
	# auto-start connections loop

	my $how_restore = !@ARGV && getPref('restore_startup') ?
		$RESTORE_ALL : $RESTORE_MAIN_RECT;

	Pub::WX::Frame::setHowRestore($how_restore);
		# apps decide how they want to restore from ini file

	my $this = $class->SUPER::new($parent);
		# Create the super class, which does the restoreState()

	# start connection from cmmand line if @ARG, or
	# any auto_start connections if not ..

	if (@ARGV)
	{
		my $connection = parseCommandLine();
		return if !$connection;
		$this->createPane($ID_CLIENT_WINDOW,undef,$connection)
	}
	elsif (!getPref('restore_startup'))
	{
		my @start_connections;
		return if !waitPrefs();
		for my $shared_connection (@{getPrefs()->{connections}})
		{
			push @start_connections,getPrefConnection(
				$shared_connection->{connection_id})
				if $shared_connection->{auto_start};
		}
		releasePrefs();
		for my $connection (@start_connections)
		{
			$this->createPane($ID_CLIENT_WINDOW,undef,$connection);
		}
	}

	# register event handlers and we're done

	EVT_MENU_RANGE($this, $COMMAND_PREFS, $COMMAND_CONNECT, \&onCommand);
    return $this;
}



sub createPane
{
	my ($this,$id,$book,$data) = @_;
	display($dbg_app,0,"fileClient::createPane($id)".
		" book="._def($book).
		" data="._def($data) );

	if ($id == $ID_CLIENT_WINDOW)
	{
	    $book ||= $this->{book};
        return apps::fileClient::Window->new($this,$id,$book,$data);
    }
    return $this->SUPER::createPane($id,$book,$data);
}


sub onCommand
{
	my ($this,$event) = @_;
	my $id = $event->GetId();

	apps::fileClient::ConnectDialog->connect() if $id == $COMMAND_CONNECT;
	apps::fileClient::PrefsDialog->editPrefs() if $id == $COMMAND_PREFS;
}



#----------------------------------------------------
# CREATE AND RUN THE APPLICATION
#----------------------------------------------------

package apps::fileClient::App;
use strict;
use warnings;
use threads;
use threads::shared;
use Pub::Utils;
use Pub::WX::Main;
use Pub::WX::AppConfig;
use apps::fileClient::Prefs;
use base 'Wx::App';

# Stuff to begin my 'standard' application

$debug_level = -5 if Cava::Packager::IsPackaged();
	# set release debug level
openSTDOUTSemaphore("buddySTDOUT") if $ARGV[0];
setStandardDataDir("buddy");

$prefs_filename = "$data_dir/fileClient.prefs";
$ini_file = "$data_dir/fileClient.ini";

my $frame;


sub OnInit
{
	$frame = apps::fileClient::AppFrame->new();
	if (!$frame)
	{
		warning(0,0,"unable to create frame");
		return undef;
	}
	$frame->Show( 1 );
	display(0,0,"fileClient.pm started");
	return 1;
}

my $app = apps::fileClient::App->new();
Pub::WX::Main::run($app);

# This little snippet is required for my standard
# applications (needs to be put into)

display(0,0,"ending fileClient.pm ...");
$frame->DESTROY() if $frame;
$frame = undef;
# display(0,0,"finished fileClient.pm");
print "fileClient closed\r\n";



1;
