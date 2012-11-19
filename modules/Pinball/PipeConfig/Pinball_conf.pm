
=pod 

=head1 NAME

    Pinball::PipeConfig::Pinball_conf;

=head1 SYNOPSIS

   # Example 1: specifying only the mandatory option (numbers to be multiplied are taken from defaults)
init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::LongMult_conf -password <mypass>

   # Example 2: specifying the mandatory options as well as overriding the default numbers to be multiplied:
init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::LongMult_conf -password <mypass> -first_mult 2344556 -second_mult 777666555

   # Example 3: do not re-create the database, just load another multiplicaton task into an existing one:
init_pipeline.pl Bio::EnsEMBL::Hive::PipeConfig::LongMult_conf -job_topup -password <mypass> -first_mult 1111222233334444 -second_mult 38578377835


=head1 DESCRIPTION

    This is the PipeConfig file for the long pinball pipeline.

    Please see the implementation details in Runnable modules themselves.

=head1 CONTACT

    Please contact avlella@gmail.com mailing list with questions/suggestions.

=cut


package Pinball::PipeConfig::Pinball_conf;

use strict;
use warnings;
use Cwd;

use base ('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');  # All Hive databases configuration files should inherit from HiveGeneric, directly or indirectly


=head2 default_options

    Description : Implements default_options() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that is used to initialize default options.
                  In addition to the standard things it defines two options, 'first_mult' and 'second_mult' that are supposed to contain the long numbers to be multiplied.

=cut

sub default_options {
    my ($self) = @_;

    return {
        'ensembl_cvs_root_dir' => $ENV{'ENSEMBL_CVS_ROOT_DIR'},
        'pipeline_name'        => 'pinball',
        'disk'                 => 1000000,
        'cluster_threads'      => 1,
        'cluster_queue'        => '',
        'cluster_gigs'         => 15,
        'overlap'              => 25,
        'csize'                => 10,
        'erate'                => 0,
        'minreadlen'           => 34,
        'dust'                 => 1,
        'rmdupfiltering'       => 1,
        'bwa_z'                => 1000,
        'allhits'              => 0,
        'longest_n'            => 1,
        'timelimit'            => 5,
        'timelimit_executable' => $ENV{'HOME'}.'/pinball/timelimit/timelimit',
        'sga_executable'       => $ENV{'HOME'}.'/pinball/sga/src/sga',
        'search_executable'    => $ENV{'HOME'}.'/pinball/bwa/bwa',
        'samtools_executable'  => $ENV{'HOME'}.'/pinball/samtools/samtools',
        'work_dir'             => $ENV{'HOME'}.'/pinball_workdir',
        'phred64'              => 0,
        'tag'                  => '',
        'extendtag'            => '',
        'control'              => '',
        'reference'            => '',
        'permute'              => '',
        'sample'               => '',
        'minclustersize'       => '',
        'maxclustersize'       => 100000,
        'cpunum'               => 8,
        'email'                => 'avilella@gmail.com',

        # 'pipeline_db' => {
        #     -host   => 'mysql-pinball',
        #     -port   => 4307,
        #     -user   => $ENV{USER},
        #     -pass   => $self->o('password'),
        #     -dbname => $ENV{USER}.'_'.$self->o('pipeline_name'),
        # },
    };
}

sub pipeline_wide_parameters {  # these parameter values are visible to all analyses, can be overridden by parameters{} and input_id{}
    my ($self) = @_;
    return {
        %{$self->SUPER::pipeline_wide_parameters},          # here we inherit anything from the base class

            'cluster_threads'   => $self->o('cluster_threads'),
            'cluster_gigs'      => $self->o('cluster_gigs'),
            'work_dir'          => $self->o('work_dir'),
            'overlap'           => $self->o('overlap'),
            'csize'             => $self->o('csize'),
            'erate'             => $self->o('erate'),
            'minreadlen'        => $self->o('minreadlen'),
            'dust'              => $self->o('dust'),
            'rmdupfiltering'    => $self->o('rmdupfiltering'),
            'bwa_z'             => $self->o('bwa_z'),
            'allhits'           => $self->o('allhits'),
            'longest_n'         => $self->o('longest_n'),
            'timelimit'         => $self->o('timelimit'),
            'timelimit_executable' => $self->o('timelimit_executable'),
            'sga_executable'    => $self->o('sga_executable'),
            'search_executable' => $self->o('search_executable'),
            'reference'         => $self->o('reference'),
            'phred64'           => $self->o('phred64'),
            'tag'               => $self->o('tag'),
            'extendtag'         => $self->o('extendtag'),
            'permute'           => $self->o('permute'),
            'sample'            => $self->o('sample'),
            'minclustersize'    => $self->o('minclustersize'),
            'maxclustersize'    => $self->o('maxclustersize'),
            'email'             => $self->o('email'),
            'cpunum'            => $self->o('cpunum'),

    };
}


=head2 pipeline_create_commands

    Description : Implements pipeline_create_commands() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that lists the commands that will create and set up the Hive database.
                  In addition to the standard creation of the database and populating it with Hive tables and procedures it also creates two pipeline-specific tables used by Runnables to communicate.

=cut

sub pipeline_create_commands {
    my ($self) = @_;
    return [
        @{$self->SUPER::pipeline_create_commands},  # inheriting database and hive tables' creation

        'mkdir -p '.$self->o('work_dir'),
    ];
}


sub resource_classes {
    my ($self) = @_;
    my $cluster_gigs_str = $self->o('cluster_gigs');
    my $initial_cluster_gigs = int($cluster_gigs_str);
    my $mem2_cluster_gigs = int($initial_cluster_gigs*2);
    my $mem3_cluster_gigs = int($initial_cluster_gigs*4);
    return {
         0 => { -desc => 'default',          'LSF' => ' -q '.$self->o('cluster_queue') },
         # 1 => { -desc => 'cluster_req',      'LSF' => ' -M'.$self->o('cluster_gigs').'000 -n '.$self->o('cluster_threads').' -q '.$self->o('cluster_queue').' -R "select[ncpus>='.$self->o('cluster_threads').' && mem>'.$self->o('cluster_gigs').'000] rusage[mem='.$self->o('cluster_gigs').'000] span[hosts=1]"' },
         1 => { -desc => 'mem1',      'LSF' => '-C0 -M'.$initial_cluster_gigs.'000 -n '.$self->o('cluster_threads').' -q '.$self->o('cluster_queue').' -R "rusage[mem='.$initial_cluster_gigs.'000] span[hosts=1]"' },
         2 => { -desc => 'mem2',      'LSF' => '-C0 -M'.$mem2_cluster_gigs.'000 -n '.$self->o('cluster_threads').' -q '.$self->o('cluster_queue').' -R "rusage[mem='.$mem2_cluster_gigs.'000] span[hosts=1]"' },
         3 => { -desc => 'mem3',      'LSF' => '-C0 -M'.$mem3_cluster_gigs.'000 -n '.$self->o('cluster_threads').' -q '.$self->o('cluster_queue').' -R "rusage[mem='.$mem3_cluster_gigs.'000] span[hosts=1]"' },
         4 => { -desc => 'run10h',      'LSF' => '-W 600' },
#        2 => { -desc => 'db_example',      'LSF' => '-R"select['.$self->o('dbresource').'<'.$self->o('dbserver_capacity').'] rusage['.$self->o('dbresource').'=10:duration=10:decay=1]"' },
    };
}


=head2 pipeline_analyses

    Description : Implements pipeline_analyses() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that defines the structure of the pipeline: analyses, jobs, rules, etc.
                  Here it defines three analyses:

                    * 'start' with two jobs (multiply 'first_mult' by 'second_mult' and vice versa - to check the commutativity of multiplivation).
                      Each job will dataflow (create more jobs) via branch #2 into 'part_multiply' and via branch #1 into 'add_together'.

                    * 'part_multiply' initially without jobs (they will flow from 'start')

                    * 'add_together' initially without jobs (they will flow from 'start').
                       All 'add_together' jobs will wait for completion of *all* 'part_multiply' jobs before their own execution (to ensure all data is available).

=cut

sub pipeline_analyses {
    my ($self) = @_;
    return [

        {   -logic_name => 'preprocess',
            -module     => 'Pinball::Preprocess',
            -parameters => {},
            -input_ids  => [ { 'seq' => $self->o('seq'), 'tag' => $self->o('tag'), 'work_dir' => $self->o('work_dir') } ],
            -flow_into => {
                1 => [ 'index' ],
            },
            -failed_job_tolerance => 100,
            -hive_capacity => 100,
        },

        {   -logic_name => 'index',
            -module     => 'Pinball::Index',
            -parameters => {},
            -flow_into => {
                2 => [ 'cluster' ],
               -1 => [ 'index_highmem2' ],
            },
            -failed_job_tolerance => 100,
            -hive_capacity => 100,
            -rc_id => 1,
        },

        {   -logic_name => 'index_highmem2',
            -module     => 'Pinball::Index',
            -parameters => {},
            -flow_into => {
                2 => [ 'cluster' ],
               -1 => [ 'index_highmem3' ],
            },
            -failed_job_tolerance => 100,
            -hive_capacity => 100,
            -rc_id => 2,
        },

        {   -logic_name => 'index_highmem3',
            -module     => 'Pinball::Index',
            -parameters => {},
            -flow_into => {
                2 => [ 'cluster' ],
            },
            -failed_job_tolerance => 100,
            -hive_capacity => 100,
            -rc_id => 3,
        },

        {   -logic_name => 'cluster',
            -module     => 'Pinball::Cluster',
            -parameters => {},
            -flow_into => {
                2 => [ 'hashcluster' ],
                1 => [ 'reportclusters','reportsearch' ],
               -1 => [ 'cluster_highmem2' ],
            },
            -failed_job_tolerance => 100,
            -hive_capacity => 20,
            -rc_id => 1,
        },

        {   -logic_name => 'cluster_highmem2',
            -module     => 'Pinball::Cluster',
            -can_be_empty  => 1,
            -parameters => {},
            -flow_into => {
                2 => [ 'hashcluster' ],
                1 => [ 'reportclusters','reportsearch' ],
               -1 => [ 'cluster_highmem3' ],
            },
            -failed_job_tolerance => 100,
            -hive_capacity => 20,
            -rc_id => 2,
        },

        {   -logic_name => 'cluster_highmem3',
            -module     => 'Pinball::Cluster',
            -can_be_empty  => 1,
            -parameters => {},
            -flow_into => {
                2 => [ 'hashcluster' ],
                1 => [ 'reportclusters','reportsearch' ],
            },
            -failed_job_tolerance => 100,
            -hive_capacity => 20,
            -rc_id => 3,
        },

        {   -logic_name => 'hashcluster',
            -module     => 'Pinball::Hashcluster',
            -parameters => {},
            -flow_into => {
                1 => [ 'walk' ],
            },
            -hive_capacity => 20,
            -failed_job_tolerance => 100,
            # input_id comes from cluster
        },

        {   -logic_name => 'walk',
            -module     => 'Pinball::Walk',
            -parameters => {},
            -flow_into => {
                3 => [ 'search' ],
            },
            -hive_capacity => 200,
            -batch_size => 1,
            # -batch_size => 20, # Better for farm setups
            -failed_job_tolerance => 100,
            # Limited to 10h
            -rc_id => 4,
            # input_id comes from cluster
        },

        {   -logic_name => 'reportclusters',
            -module     => 'Pinball::ReportClusters',
            -hive_capacity => $self->o('cpunum'),
            -failed_job_tolerance => 100,
            -parameters => {},
            -wait_for => [ 'walk' ],   # comes from the first analysis
        },

        # Search and ReportSearch analyses will only be done if 'reference' is specified
        ('' ne $self->o('reference') ?
            {   -logic_name => 'search',
                -module     => 'Pinball::Search',
                -hive_capacity => 200,
                -batch_size => 1,
                # -batch_size => 20, # Better for farm setups
                -failed_job_tolerance => 100,
            }
        : () ),
        ('' ne $self->o('reference') ?
            {   -logic_name => 'reportsearch',
                -module     => 'Pinball::ReportSearch',
                -hive_capacity => $self->o('cpunum'),
                -failed_job_tolerance => 100,
                -parameters => {},
                -wait_for => [ 'walk', 'search' ],   # comes from the first analysis
            }
        : () ),

        # Control analysis will only be done if 'control' is specified
        ('' ne $self->o('control') ?
            {   -logic_name => 'control',
                -module     => 'Pinball::Control',
                -input_ids  => [ { 'seq' => $self->o('seq'), 'control' => $self->o('control'), 'tag' => $self->o('tag'), 'work_dir' => $self->o('work_dir') } ],
                -hive_capacity => $self->o('cpunum'),
                -failed_job_tolerance => 100,
                -parameters => {},
                -wait_for => [ 'reportclusters' ],
            }
        : () ),
    ];
}

1;

