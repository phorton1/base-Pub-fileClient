#!/usr/bin/perl
#------------------------------------------------------------
# fileClientWindow
#------------------------------------------------------------
# Creates a connection (ClientSession) to a SerialBridge
# Handles asyncrhonouse messages from the SerialBridge
# Is assumed to be Enabled upon connection.

#    EXIT - close the window, and on the last window, closes the App
#    DISABLE/ENABLE - posts a RED or GREEN message and enables or
#    disables the remote pane


package apps::fileClient::Window;
use strict;
use warnings;
use threads;
use threads::shared;
use Wx qw(:everything);
use Wx::Event qw(
	EVT_SIZE );
use Pub::Utils;
use Pub::WX::Window;
use Pub::FS::ClientSession;		# for $DEFAULT_PORT
use apps::fileClient::Pane;
use apps::fileClient::fcPrefs;
use apps::fileClient::Resources;
use apps::fileClient::PaneThread;
use apps::fileClient::PaneCommand;
use base qw(Pub::WX::Window);


my $dbg_fcw = 0;
	# 0 = new() and onClose calls
	# -1 = new() header

my $PAGE_TOP = 30;
my $SPLITTER_WIDTH = 10;
my $INITIAL_SPLITTER = 460;

my $instance = 0;

my $title_font = Wx::Font->new(9,wxFONTFAMILY_DEFAULT,wxFONTSTYLE_NORMAL,wxFONTWEIGHT_BOLD);
my $color_red  = Wx::Colour->new(0xc0 ,0x00, 0x00);  # red


sub getBestPaneName
	# getAppFrame()has all the panes
	# same for the concept of the active frame ...
{
	my ($this,$name) = @_;
	$name ||= 'untitled';
	display(0,0,"getBestPaneName($name)");

	my %other_nums;
	my $app_frame = getAppFrame();
    for my $pane (@{$app_frame->{panes}})
	{
		my $other_name = $pane->{name};
		display(0,1,"other_name=$other_name");

		if ($other_name =~ /^$name(.*)$/)
		{
			my $with_parens = $1 || '';
			my $other_num = $with_parens =~ /^\((\d+)\)$/ ? $1 : 0;
			display(0,2,"other_num=$other_num");
			$other_nums{$other_num} = 1;
		}
	}

	my $num = 0;
	while ($other_nums{$num}) {$num++};

	$name .= "($num)" if $num;
	return $name;
}


sub getWinConnection
{
	my ($this) = @_;
	return $this->{connection};
}


#---------------------------
# new
#---------------------------

sub new
	# the 'data' member is the name of the connection information
{
	my ($class,$frame,$id,$book,$connection) = @_;
	$connection ||= '';
	display($dbg_fcw+1,0,"apps::fileClient::Window::new connection=$connection");

	if (!$connection)
	{
		error("No connection specified");
		return;
	}

	# if constructed from restoreState(), the sash pos will be
	# in the connection

	my $sash_pos = $connection->{sash_pos} || $INITIAL_SPLITTER;

	my $this = $class->SUPER::new($book,$id);
	my $name = $this->getBestPaneName($connection->{connection_id});

	$instance++;
	display($dbg_fcw,0,"apps::fileClient::Window::new($name) instance=$instance");
	$this->MyWindow($frame,$book,$id,$name,$connection,$instance);
	$this->{name} = $name;

	$this->{connection} = $connection;
    $this->{follow_dirs} = Wx::CheckBox->new($this,-1,'follow dirs',[10,5],[-1,-1]);

	my $ctrl1 = Wx::StaticText->new($this,-1,'',[100,5]);
	$ctrl1->SetFont($title_font);
	my $ctrl2 = Wx::StaticText->new($this,-1,'',[$sash_pos + 10,5]);
	$ctrl2->SetFont($title_font);

	# we copy the params into new hashes so that
	# $this->{connection} is a benign hash for json
	# in getDataForIniFile()

	my $params0 = {};
	my $params1 = {};
	mergeHash($params0,$connection->{params}->[0]);
	mergeHash($params1,$connection->{params}->[1]);
	$params0->{pane_num} = 0;
	$params1->{pane_num} = 1;
	$params0->{enabled_ctrl} = $ctrl1;
	$params1->{enabled_ctrl} = $ctrl2;

    $this->{splitter} = Wx::SplitterWindow->new($this, -1, [0, $PAGE_TOP]); # ,[400,400], wxSP_3D);
    my $pane0 = $this->{pane0} = apps::fileClient::Pane->new($this,$this->{splitter},$params0);
    my $pane1 = $this->{pane1} = apps::fileClient::Pane->new($this,$this->{splitter},$params1);

	if (!$pane0 || !$pane1)
	{
		error("Could not create pane0("._def($pane0)." or pane1("._def($pane1).")");
		return;
	}

    $this->{splitter}->SplitVertically($pane0,$pane1,$sash_pos);

	$pane0->{other_pane} = $pane1;
	$pane1->{other_pane} = $pane0;

    $this->doLayout();

	$pane0->setContents();
	$pane1->setContents();

	$this->populate();

    # Finished

    EVT_SIZE($this,\&onSize);
	return $this;
}


sub populate
{
	my ($this) = @_;
	if (!$this->{pane0}->{thread} &&
		!$this->{pane1}->{thread})
	{
		$this->{pane0}->populate(1);
		$this->{pane1}->populate(1);
	}
}


sub onClose
{
	my ($this,$event) = @_;
	display($dbg_fcw,0,"FC::Window::onClose() called");

	# The sub-windows do not receive the EVT_CLOSE,
	# even if they register for it, so we have to
	# call doClose explicitly

	$this->{pane0}->doClose($event);
	$this->{pane1}->doClose($event);

	$this->SUPER::onClose($event);
	$event->Skip();
}



sub doLayout
{
	my ($this) = @_;
	my $sz = $this->GetSize();
    my $width = $sz->GetWidth();
    my $height = $sz->GetHeight();
    $this->{splitter}->SetSize([$width,$height-$PAGE_TOP]);
}



sub onSize
{
    my ($this,$event) = @_;
	$this->doLayout();
    $event->Skip();
}



sub getDataForIniFile
	# Return a data object (or '') to be jsonified
	# and stored in the ini file to later be de-jsonified
	# and retured as the $data param during window ctor.
	# DATA CANNOT CONTAIN \n and
	# MUST BE PURE SIMPLE PERL scalar, hash, or array
{
	my ($this) = @_;
	my $pane0 = $this->{pane0};
	my $pane1 = $this->{pane1};
	my $connection = $this->{connection};
	my $params0 = $connection->{params}->[0];
	my $params1 = $connection->{params}->[1];

	# add the splitter position to the saved info

	my $sash_pos = $this->{splitter}->GetSashPosition();
	$connection->{sash_pos} = $sash_pos;

	# use the current pane {dirs}

	$params0->{dir} = $pane0->{dir};
	$params1->{dir} = $pane1->{dir};

	# add column info

	$params0->{col_info} = $pane0->getColumnInfo();
	$params1->{col_info} = $pane1->getColumnInfo();

	# return for jsonify

	return $connection;
}



1;
