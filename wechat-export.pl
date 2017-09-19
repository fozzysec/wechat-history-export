#!/usr/bin/env perl
# Wechat chat history export tool by Fozzy Hou (fozzy@fozzy.co)
#
use DBI;
use File::Basename;
use Encode qw/decode_utf8/;
use Data::Dumper;
use HTML::TagTree;
use File::Path;
use File::Copy::Recursive qw/dircopy/;
use Digest::MD5 qw(md5_hex);
use feature qw/say/;
use utf8;

my $driver = "SQLite";
my $wechatdir = $ARGV[0];
die "Usage: " . basename($0)."wechatdir" if(!defined($wechatdir));
opendir(MAINDIR, $wechatdir) or die "$wechatdir: $!";
my @userlist = ();
while(my $dirname = readdir(MAINDIR)){
	if(length($dirname) == 32 && $dirname != '0'x32){
		say "found records for user: ". $dirname;
		push @userlist, $dirname;
	}
}
closedir(MAINDIR);

for(@userlist){
	$_ = $wechatdir . '/'. $_;
}
for my $currentuser (@userlist){
	my @user_dir = ($currentuser.'/DB', $currentuser.'/Img');
	my $user_MM = $user_dir[0].'/MM.sqlite';
	my $user_contacts = $user_dir[0].'/WCDB_Contact.sqlite';
	my $mm_connstr = "DBI:$driver:dbname=$user_MM";
	my $contact_connstr = "DBI:$driver:dbname=$user_contacts";

	my $mm_dbh = DBI->connect($mm_connstr, "", "", {RaiseError => 1})
		or die $DBI::errstr;
	my $contact_dbh = DBI->connect($contact_connstr, "", "", {RaiseError => 1})
		or die $DBI::errstr;
	say "successfully opened $user_MM, $user_contacts";
	my $sql = q/SELECT tbl_name FROM sqlite_master WHERE type = 'table' AND tbl_name LIKE 'Chat\_%' ESCAPE '\';/;
	my $result = $mm_dbh->prepare($sql);
	my $rv = $result->execute() or die $DBI::errstr;
	if($rv < 0){
		die $DBI::errstr;
	}
	my @chats = ();
	while(my @row = $result->fetchrow_array()){
		say "$currentuser: chat log table $row[0] found";
		push @chats, $row[0];
	}

	my @contacts;
	$sql = q/SELECT userName FROM Friend;/;
	$result = $contact_dbh->prepare($sql);
	$rv = $result->execute() or die $DBI::errstr;
	if($rv < 0){
		die $DBI::errstr;
	}
	while(my @row = $result->fetchrow_array()){
		say "$currentuser: contacts $row[0] found";
		push @contacts, {md5_hex($row[0]) => $row[0]};
	}
	my @contacts_wechatid = ();
	foreach my $chat (@chats){
		foreach(@contacts){
			my $hash = $_;
			my @indexes =keys $_;
			my $key = shift @indexes;
			if($chat =~ /$key/){
				push @contacts_wechatid, {$chat => $$hash{$key}};
			}
		}
	}
	my $currentid;
	@_ = split('/', $currentuser);
	$currentid = pop @_;
	say $currentid;
	mkpath('report/'.$currentid);
	dircopy($user_dir[1], 'report/'.$currentid.'/Img');
	foreach(@contacts_wechatid){
		my @indexes = keys $_;
		my $key = shift @indexes;
		open(FH, '>:encoding(utf-8)', 'report/'.$currentid.'/'. $$_{$key} . ".html") or die "Can not open file for write: $!";
		my $html = HTML::TagTree->new('html');
		my $head = $html->head;
		$head->title("Chat log with $$_{$key}");
		$head->meta('', 'charset="UTF-8"');
		my $body = $html->body;
		$body->p("Chat history with $$_{$key}:");
		my $tbl = $body->table('', 'border="1"');
		my $heading = $tbl->tr;
		$heading->th("ID");
		$heading->th("Time");
		$heading->th("Send/Receive");
		$heading->th("Type");
		$heading->th("Message");
		$heading->th("Status");
		$sql = qq/SELECT MesLocalID, CreateTime, Message, Status, Type, Des FROM $key;/;
		$result = $mm_dbh->prepare($sql);
		$rv = $result->execute() or die $DBI::errstr;
		if($rv < 0){
			die $DBI::errstr;
		}
		while(my @row = $result->fetchrow_array()){
			my $id, $status, $time, $message, $type, $sr;
			$id = $row[0];
			if($row[5] == 0){
				$sr = "send";
			}
			elsif($row[5] == 1){
				$sr = "receive";
			}
			else{
				$sr = "unknown";
			}
			#Status
			if($row[3] == 2){
				$status = "Successfully Send";

			}
			elsif($row[3] == 4){
				$status = "Successfully Received";
			}
			else{
				$status = "Unsuccessful";
			}
			$time = scalar localtime($row[1]);
			#Type
			#text
			if($row[4] == 1){
				$type = "text";
				$message = $row[2];
			}
			#image
			elsif($row[4] == 3){
				$type = "image";
				my $md5 = md5_hex($$_{$key});
				$message = "<a href=\"Img/$md5/$id.pic\">View</a>";
			}
			elsif($row[4] == 6){
				$type = $message = "file";
			}
			elsif($row[4] == 17){
				$type = $message = "Real-time Location";
			}
			elsif($row[4] == 34){
				$type = $message = "voice";
			}
			elsif($row[4] == 42){
				$type = $message = "userNamecard";
			}
			elsif($row[4] == 47){
				$type = $message = "emoticon";
			}
			elsif($row[4] == 48){
				$type = $message = "Location";
			}
			elsif($row[4] == 49){
				$type = $message = "Links";
			}
			elsif($row[4] == 50){
				$type = $message = "Voice/Video Call";
			}
			elsif($row[4] == 62){
				$type = $message = "Video";
			}
			elsif($row[4] == 10000){
				$type = "System Message";
				$message = $row[2];
			}
			else{
				$type = "Other";
				$message = "Unknown";
			}
			$message = Encode::decode_utf8($message);

			my $tbl_row = $tbl->tr;
			$tbl_row->td($id);
			$tbl_row->td($time);
			$tbl_row->td($sr);
			$tbl_row->td($type);
			$tbl_row->td($message);
			$tbl_row->td($status);
		}
		print FH $html->get_html_text();
		close(FH);
	}
	$mm_dbh->disconnect();
	$contact_dbh->disconnect();
}
