package WebGUI::Storage;

=head1 LEGAL 

 -------------------------------------------------------------------
  WebGUI is Copyright 2001-2004 Plain Black Corporation.
 -------------------------------------------------------------------
  Please read the legal notices (docs/legal.txt) and the license
  (docs/license.txt) that came with this distribution before using
  this software.
 -------------------------------------------------------------------
  http://www.plainblack.com                     info@plainblack.com
 -------------------------------------------------------------------

=cut

use Archive::Tar;
use File::Copy qw(cp);
use FileHandle;
use File::Path;
use POSIX;
use strict;
use warnings;
use WebGUI::ErrorHandler;
use WebGUI::Id;
use WebGUI::Session;
use WebGUI::Utility;

=head1 NAME

Package WebGUI::Storage

=head1 DESCRIPTION

This package provides a mechanism for storing and retrieving files that are not put into the database directly.

=head1 SYNOPSIS

 use WebGUI::Storage;
 $store = WebGUI::Storage->create;
 $store = WebGUI::Storage->get($id);

 $filename = $store->addFileFromFilesystem($pathToFile);
 $filename = $store->addFileFromFormPost($formVarName);
 $filename = $store->addFileFromHashref($filename,$hashref);
 $filename = $store->addFileFromScalar($filename,$content);

 $integer = $store->getErrorCount;
 $hashref = $store->getFileContentsAsHashref($filename);
 $string = $store->getFileContentsAsScalar($filename);
 $string = $store->getFileExtension($filename);
 $url = $store->getFileIconUrl($filename);
 $arrayref = $store->getFiles;
 $string = $store->getFileSize($filename);
 $guid = $store->getId;
 $string = $store->getLastError;
 $string = $store->getPath($filename);
 $string = $store->getUrl($filename);

 $newstore = $store->copy;
 $newstore = $store->tar($filename);
 $newstore = $store->untar($filename);


 $store->delete;
 $store->deleteFile($filename);
 $store->rename($filename, $newFilename);
 $store->setPrivileges($userId, $groupIdView, $groupIdEdit);

=head1 METHODS

These methods are available from this package:

=cut


#-------------------------------------------------------------------

=head2 _addError ( errorMessage )

Adds an error message to the object.

NOTE: This is a private method and should never be called except internally to this package.

=head3 errorMessage

The error message to add to the object.

=cut

sub _addError {
	my $self = shift;
	my $errorMessage = shift;
	push(@{$self->{_errors}},$errorMessage);
	WebGUI::ErrorHandler::warn($errorMessage);
}


#-------------------------------------------------------------------

=head2 _makePath ( )

Creates the filesystem folders for a storage location.

NOTE: This is a private method and should never be called except internally to this package.

=cut

sub _makePath {
	my $self = shift;
	my $node = $session{config}{uploadsPath};
	foreach my $folder ($self->{_part1}, $self->{_part2}, $self->{_id}) {
		$node .= $session{os}{slash}.$folder;
		unless (-e $node) { # check to see if it already exists
			unless (mkdir($node)) { # check to see if there was an error during creation
				$self->_addError("Couldn't create storage location: $node : $!");
			}
		}
	}
}

#-------------------------------------------------------------------

=head2 addFileFromFilesystem( pathToFile )

Grabs a file from the server's file system and saves it to a storage location and returns a URL compliant filename.

=head3 pathToFile

Provide the local path to this file.

=cut

sub addFileFromFilesystem {
	my $self = shift;
	my $pathToFile = shift;
	my $filename;
        if (defined $pathToFile) {
                if ($pathToFile =~ /([^\/\\]+)$/) {
                        $filename = $1;
                } else {
                        $pathToFile = $filename;
                }
                if (isIn($self->getFileExtension, qw(pl perl sh cgi php asp))) {
                        $filename =~ s/\./\_/g;
                        $filename .= ".txt";
                }
                $filename = WebGUI::URL::makeCompliant($filename);
                if (-d $pathToFile) {
                        WebGUI::ErrorHandler::warn($pathToFile." is a directory, not a file.");
                } else {
                        $a = FileHandle->new($pathToFile,"r");
                        if (defined $a) {
                                binmode($a);
                                $b = FileHandle->new(">".$self->getPath($filename));
                                if (defined $b) {
                                        binmode($b);
                                        cp($a,$b) or $self->_addError("Couldn't copy $pathToFile to ".$self->getPath($filename).": $!");
                                        $b->close;
                                } else {
                                        $self->_addError("Couldn't open file ".$self->getPath($filename)." for writing due to error: ".$!);
                                        $filename = undef;
                                }
                                $a->close;
                        } else {
                                $self->_addError("Couldn't open file ".$pathToFile." for reading due to error: ".$!);
                                $filename = undef;
                        }
                }
        } else {
                $filename = undef;
        }
        return $filename;
}


#-------------------------------------------------------------------

=head2 addFileFromFormPost ( formVariableName )

Grabs an attachment from a form POST and saves it to this storage location.

=head3 formVariableName

Provide the form variable name to which the file being uploaded is assigned. Note that if multiple files are uploaded with the same formVariableName then they'll all be stored in the storage location, but only the last filename will be returned. Use the getFiles() method on the storage location to get all the filenames stored.

=cut

sub addFileFromFormPost {
	my $self = shift;
	my $formVariableName = shift;
        return "" if (WebGUI::HTTP::getStatus() =~ /^413/);
	my $filename;
        foreach my $tempPath ($session{cgi}->upload($formVariableName)) {
                if ($tempPath =~ /([^\/\\]+)$/) {
                        $filename = $1;
                } else {
                        $filename = $tempPath;
                }
                my $type = $self->getFileExtension($filename);
                if (isIn($type, qw(pl perl sh cgi php asp))) { # make us safe from malicious uploads
                        $filename =~ s/\./\_/g;
                        $filename .= ".txt";
                }
                $filename = WebGUI::URL::makeCompliant($filename);
		my $bytesread;
                my $file = FileHandle->new(">".$self->getPath($filename));
                if (defined $file) {
			my $buffer;
                        binmode $file;
                        while ($bytesread=read($tempPath,$buffer,1024)) {
                                print $file $buffer;
                        }
                        close($file);
                } else {
                        $self->_addError("Couldn't open file ".$self->getPath($filename)." for writing due to error: ".$!);
                        return undef;
                }
        }
        return $filename;
}


#-------------------------------------------------------------------
                                                                                                                                                       
=head2 addFileFromHashref ( filename, hashref )
                                                                                                                                                       
Stores a hash reference as a file and returns a URL compliant filename. Retrieve the data with getFileContentsAsHashref.

=head3 filename

The name of the file to create.
                                                                                                                                                       
=head3 hashref
                                                                                                                                                       
A hash reference containing the data you wish to persist to the filesystem.
                                                                                                                                                       
=cut
                                                                                                                                                       
sub addFileFromHashref {
	my $self = shift;
	my $filename = WebGUI::URL::makeCompliant(shift);
	my $hashref = shift;
        store $hashref, $self->getPath($filename) or $self->_addError("Couldn't create file ".$self->getPath($filename)." because ".$!);
	return $filename;
}

#-------------------------------------------------------------------

=head2 addFileFromScalar ( filename, content )

Adds a file to this storage location and returns a URL compliant filename.

=head3 filename

The filename to create.

=head3 content

The content to write to the file.

=cut

sub addFileFromScalar {
	my $self = shift;
	my $filename = WebGUI::URL::makeCompliant(shift);
	my $content = shift;
	if (open(FILE,">".$self->getPath($filename))) {
		print FILE $content;
		close(FILE);
	} else {
        	$self->_addError("Couldn't create file ".$self->getPath($filename)." because ".$!);
	}
	return $filename;
}


#-------------------------------------------------------------------
                                                                                                                                                       
=head2 copy ( )
                                                                                                                                                       
Copies a storage location and it's contents. Returns a new storage location object. Note that this does not copy privileges or other special filesystem properties.
                                                                                                                                                       
=cut
                                                                                                                                                       
sub copy {
	my $self = shift;
	my $newStorage = WebGUI::Storage->create;
	my $filelist = $self->getFiles;
	foreach my $file (@{$filelist}) {	
        	$a = FileHandle->new($self->getPath($file),"r");
        	if (defined $a) {
                	binmode($a);
                	$b = FileHandle->new(">".$newStorage->getPath($file));
                	if (defined $b) {
                        	binmode($b);
                        	cp($a,$b) or $self->_addError("Couldn't copy file ".$self->getPath($file)." to ".$newStorage->getPath($file)." because ".$!);
                        	$b->close;
                	}
                	$a->close;
        	}
	}
	return $newStorage;
}

#-------------------------------------------------------------------

=head2 create ( )
 
Creates a new storage location on the file system.

=cut

sub create {
	my $class = shift;
	my $id = WebGUI::Id::generate();
	my $self = $class->get($id); 
	$self->_makePath;
	return $self; 
}

#-------------------------------------------------------------------

=head2 delete ( )

Deletes this storage location and its contents (if any) from the filesystem and destroy's the object.

=cut

sub delete {
	my $self = shift;
        rmtree($self->getPath);
	undef $self;
}

#-------------------------------------------------------------------
                                                                                                                                                       
=head2 deleteFile ( filename )
                                                                                                                                                       
Deletes a file from it's storage location.

=head3 filename

The name of the file to delete.
                                                                                                                                                       
=cut
                                                                                                                                                       
sub deleteFile {
	my $self = shift;
	my $filename = shift;
        unlink($self->getPath($filename));
}


#-------------------------------------------------------------------

=head2 get ( id )

Returns a WebGUI::Storage object.

=head3 id 

The unique identifier for this file system storage location.

=cut

sub get {
	my $class = shift;
	my $id = shift;
	$id =~ m/^(.{2})(.{2})/;
	my $self = {_id => $id, _part1 => $1, _part2 => $2};
	bless $self, ref($class)||$class;
	$self->_makePath unless (-e $self->getPath); # create the folder in case it got deleted somehow
	return $self;
}

#-------------------------------------------------------------------

=head2 getErrorCount ( )

Returns the number of errors that have been generated on this object instance.

=cut

sub getErrorCount {
	my $self = shift;
	my $count = scalar(@{$self->{_errors}});
	return $count;
}


#-------------------------------------------------------------------

=head2 getFileContentsAsScalar ( filename )

Reads the contents of a file into a scalar variable and returns the scalar.

=head3 filename

The name of the file to read from.

=cut

sub getFileContentsAsScalar {
	my $self = shift;
	my $filename = shift;
	my $content;
	open (FILE,"<".$self->getPath($filename));
	while (<FILE>) {
		$content .= $_;
	}
	close(FILE);
	return $content;
}


#-------------------------------------------------------------------
                                                                                                                                                       
=head2 getFileExtension ( filename )
                                                                                                                                                       
Returns the extension or type of this file.

=head3 filename

The filename of the file you wish to find out the type for.
                                                                                                                                                       
=cut
                                                                                                                                                       
sub getFileExtension {
	my $self = shift;
	my $filename = shift;
        my $extension = lc($filename);
        $extension =~ s/.*\.(.*?)$/$1/;
        return $extension;
}


#-------------------------------------------------------------------

=head2 getFileIconUrl ( filename ) 

Returns the icon associated with this type of file.

=head3 filename

The name of the file to get the icon for.

=cut

sub getFileIconUrl {
	my $self = shift;
	my $filename = shift;
	my $extension = $self->getFileExtension($filename);	
	my $path = $session{config}{extrasPath}.$session{os}{slash}."fileIcons".$session{os}{slash}.$extension.".gif";
	if (-e $path) {
		return $session{config}{extrasURL}."/fileIcons/".$extension.".gif";
	}
	return $session{config}{extrasURL}."/fileIcons/unknown.gif";
}


#-------------------------------------------------------------------
                                                                                                                                                       
=head2 getFileSize ( filename )
                                                                                                                                                       
Returns the size of this file.
                                                                                                                                                       
=cut
                                                                                                                                                       
sub getFileSize {
	my $self = shift;
	my $filename = shift;
        my (@attributes) = stat($self->getPath($filename));
        return $attributes[7];
}


#-------------------------------------------------------------------

=head2 getFiles ( )

Returns an array reference of the files in this storage location.

=cut

sub getFiles {
	my $self = shift;
	my @list;
	if (opendir (DIR,$self->getPath)) {
        	my @files = readdir(DIR);
        	closedir(DIR);
        	foreach my $file (@files) {
                	unless ($file =~ m/^\./) { # don't show files starting with a dot
				push(@list,$file);
			}
                }
		return \@list;
        }
	return undef;
}



#-------------------------------------------------------------------
                                                                                                                                                       
=head2 getFileContentsAsHashref ( filename )
                                                                                                                                                       
Returns a hash reference from the file. Must be used in conjunction with a file that was saved using the addFileFromHashref method.

=head3 filename

The file to retrieve the data from.
                                                                                                                                                       
=cut
                                                                                                                                                       
sub getHashref {
	my $self = shift;
	my $filename = shift;
        return retrieve($self->getPath($filename));
}



#-------------------------------------------------------------------

=head2 getId ()

Returns the unique identifier of this storage location.

=cut

sub getId {
	my $self = shift;
	return $self->{_id};
}

#-------------------------------------------------------------------

=head2 getLastError ()

Returns the most recently generated error message.

=cut

sub getLastError {
	my $self = shift;
	my $count = $self->getErrorCount;
	return $self->{_errors}[$count-1];
}


#-------------------------------------------------------------------

=head2 getPath ( [ file ] )

Returns a full path to this storage location.

=head3 file

If specified, we'll return a path to the file rather than the storage location.

=cut

sub getPath {
	my $self = shift;	
	my $file = shift;
        my $path = $session{config}{uploadsPath}
		.$session{os}{slash}.$self->{_part1}
		.$session{os}{slash}.$self->{_part2}
		.$session{os}{slash}.$self->getId;
        if (defined $file) {
                $path .= $session{os}{slash}.$file;
        }
        return $path;
}


#-------------------------------------------------------------------

=head2 getUrl ( [ file ] )

Returns a URL to this storage location.

=head3 file

If specified, we'll return a URL to the file rather than the storage location.

=cut

sub getUrl {
	my $self = shift;
	my $file = shift;
	my $url = $session{config}{uploadsURL}.'/'.$self->{_part1}.'/'.$self->{_part2}.'/'.$self->getId;
	if (defined $file) {
		$url .= '/'.$file;
	}
	return $url;
}

                                                                                                                                                       
#-------------------------------------------------------------------
                                                                                                                                                       
=head2 renameFile ( filename, newFilename )

Renames an file's filename.

=head3 filename

The name of the file you wish to rename.
                                                                                                               
=head3 newFilename

Define the new filename a specified file.

=cut
                                                                                                                                                       
sub renameFile {
	my $self = shift;
	my $filename = shift;
	my $newFilename = shift;
        rename $self->getPath($filename), $self->getNode->getPath($newFilename);
}


#-------------------------------------------------------------------

=head2 setPrivileges ( ownerUserId, groupIdView, groupIdEdit )

Set filesystem level privileges for this file. Used with the uploads access handler.

=head3 ownerUserId

The userId of the owner of this storage location.

=head3 groupIdView

The groupId that is allowed to view the files in this storage location.

=head3 groupIdEdit

The groupId that is allowed to edit the files in this storage location.

=cut

sub setPrivileges {
	my $self = shift;
	my $owner = shift;
	my $viewGroup = shift;
	my $editGroup = shift;
	$self->addFileFromScalar(".wgaccess",$owner."\n".$viewGroup."\n".$editGroup);
}



#-------------------------------------------------------------------

=head2 tar ( filename )

Archives this storage location into a tar file and then compresses it with a zlib algorithm. It then returns a new WebGUI::Storage object for the archive.

=head3 filename

The name of the tar file to be created. Should ideally end with ".tar.gz".

=cut

sub tar {
	my $self = shift;
	my $filename = shift;
	chdir $self->getPath;
	my $temp = WebGUI::Node->create;
	if ($Archive::Tar::VERSION eq '0.072') {
		my $tar = Archive::Tar->new();
		$tar->add_files($self->getFiles);
		$tar->write($temp->getPath($filename),1);
		
	} else {
		Archive::Tar->create_archive($temp->getPath($filename),1,$self->getFiles);
	}
	return $temp;
}

#-------------------------------------------------------------------

=head2 untar ( filename )

Unarchives a file into a new storage location. Returns the new WebGUI::Storage object.

=head3 filename

The name of the tar file to be untarred.

=cut

sub untar {
        my $self = shift;
	my $filename = shift;
	my $temp = WebGUI::Node->create;
        chdir $temp->getPath;
	Archive::Tar->extract_archive($self->getPath($filename),1);
	$self->_addError(Archive::Tar->error) if (Archive::Tar->error);
}


1;


