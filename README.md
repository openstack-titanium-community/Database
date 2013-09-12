Database
========

Here are the steps and configuration required to get the current version of the Percona XtraDB Cluster cookbook going

1) pull current version of cookbook from here. (this is the chef-philipper cookbook with modifications for cluster startup & bootstrap-pxc)
The fork from rochfordk/chef-percona is included as a submodule so you'll need to use a recursive fetch (git fetch --all --recurse-submodules)

2) Modifications required to default attributes file (A working sample is provided under the configuration directory)

Line 32 (comment out. Reason: Prevents successful startup)
  # default["percona"]["server"]["pidfile"]                       = "/var/run/mysqld/mysqld.pid"


Line 42 (change path to my.cnf)
default["percona"]["main_config_file"]                          = "/etc/mysql/my.cnf"


Line 49 (change role to 'cluster')
default["percona"]["server"]["role"] = "cluster"


Line 144 onwards -  XtraDB Cluster Settings

change to 32 bit galera library (64 can prevent successful startup)
default["percona"]["cluster"]["wsrep_provider"]                 = "/usr/lib/libgalera_smm.so"

Set cluster address to include IPs of all DB cluster nodes. e.g.
default["percona"]["cluster"]["wsrep_cluster_address"]          = "gcomm://10.125.0.14,10.125.0.15,10.125.0.16"

Assign a cluster name
default["percona"]["cluster"]["wsrep_cluster_name"]             = "COEc1"

Change SST (snapshot state transfer) method to xtrabackup and set auth credentials (these will later be taken from an ecrypted data-bag)
default["percona"]["cluster"]["wsrep_sst_method"]               = "xtrabackup"
default["percona"]["cluster"]["wsrep_sst_auth"]                 = "sstuser:s3cretPass"

* NB KR - check if eth0 in template and recipe file
