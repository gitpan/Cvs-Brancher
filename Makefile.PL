use ExtUtils::MakeMaker;

my %opts = (
	    'NAME'	   => 'Cvs::Brancher',
	    'VERSION_FROM' => 'lib/Cvs/Brancher.pm',
	    'EXE_FILES'    => [ 
				'scripts/branch.pl',
				'scripts/scheduled_build.pl'
				],
	    'PREREQ_PM'    => {
                'Carp'           => 1.01,
                'Pod::Usage'     => 1.14,
                'Getopt::Long'   => 2.25,
                'File::Basename' => 2.6,
                'File::Copy'     => 2.03,
                'File::Find'     => 1.04,
                'File::Path'     => 1.0404,
                'File::Spec'     => 0.82,
		'Mail::Sender'   => 0.8,
                'Template'       => 2.06,
                },
);

if ($ExtUtils::MakeMaker::VERSION >= 5.43) {
    $opts{AUTHOR}   = 'Bryce Harrington';
    $opts{ABSTRACT} = 'Creates and merges CVS branches';
}

WriteMakefile( %opts )

