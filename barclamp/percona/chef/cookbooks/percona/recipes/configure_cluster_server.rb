percona = node["percona"]
server  = percona["server"]
conf    = percona["conf"]
mysqld  = (conf && conf["mysqld"]) || {}
firstnode = false
headnode = ""

# get ip addresses - Barclamp proposal needs to be coded and not hard coded
getdbip_db = data_bag_item('crowbar', 'bc-percona-proposal')
dbcont1 = getdbip_db["deployment"]["percona"]["elements"]["percona"][0]
dbcont2 = getdbip_db["deployment"]["percona"]["elements"]["percona"][1]
dbcont3 = getdbip_db["deployment"]["percona"]["elements"]["percona"][2]
cont_db = data_bag_item('crowbar', 'admin_network')
cont1_admin_ip = cont_db["allocated_by_name"]["#{dbcont1}"]["address"]
cont2_admin_ip = cont_db["allocated_by_name"]["#{dbcont2}"]["address"]
cont3_admin_ip = cont_db["allocated_by_name"]["#{dbcont3}"]["address"]
gcommaddr = "gcomm://" +  cont1_admin_ip + "," + cont2_admin_ip + "," + cont3_admin_ip


# construct an encrypted passwords helper -- giving it the node and bag name
passwords = EncryptedPasswords.new(node, percona["encrypted_data_bag"])

template "/root/.my.cnf" do
  variables(:root_password => passwords.root_password)
  owner "root"
  group "root"
  mode 0600
  source "my.cnf.root.erb"
end

if server["bind_to"]
  ipaddr = Percona::ConfigHelper.bind_to(node, server["bind_to"])
  if ipaddr && server["bind_address"] != ipaddr
    node.override["percona"]["server"]["bind_address"] = ipaddr
    node.save
  end

  log "Can't find ip address for #{server["bind_to"]}" do
    level :warn
    only_if { ipaddr.nil? }
  end
end

datadir = mysqld["datadir"] || server["datadir"]
user    = mysqld["username"] || server["username"]

# define the service
service "mysql" do
  supports :restart => true
  
  #If this is the first node we'll change the start and resatart commands to take advantage of the bootstrap-pxc command
  #Get the cluster address and extract the first node IP

  #cluster_address = node["percona"]["cluster"]["wsrep_cluster_address"].dup
  #cluster_address.slice! "gcomm://"
  #cluster_nodes = cluster_address.split(',')
  headnode = cont1_admin_ip 
  localipaddress= Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address 
  # localipaddress=  node["network"]["interfaces"]["eth0"]["addresses"].select {|address, data| data["family"] == "inet" }.first.first
  if cont1_admin_ip == localipaddress
	firstnode = true
	start_command "/usr/bin/service mysql bootstrap-pxc" #if platform?("ubuntu")
	restart_command "/usr/bin/service mysql stop && /usr/bin/service mysql bootstrap-pxc" #if platform?("ubuntu")
  end
  
  
  
  action server["enable"] ? :enable : :disable
end

# this is where we dump sql templates for replication, etc.
directory "/etc/mysql" do
  owner "root"
  group "root"
  mode 0755
end

# setup the data directory
directory datadir do
  owner user
  group user
  recursive true
  action :create
end

# install db to the data directory
execute "setup mysql datadir" do
  command "mysql_install_db --user=#{user} --datadir=#{datadir}"
  not_if "test -f #{datadir}/mysql/user.frm"
end


# setup the main server config file
template percona["main_config_file"] do
  source "my.cnf.#{conf ? "custom" : server["role"]}.erb"
  owner "root"
  group "root"
  mode "0744"
  variables( {
    "gcommaddr" => gcommaddr
  } )


  # If this is not the first node wait until the first node becomes available before restarting the service
  if firstnode
	notifies :restart, "service[mysql]", :immediately if node["percona"]["auto_restart"]
  else
	Chef::Log.info("****COE-LOG: Checking for MySQL service on #{headnode}, port 4567")
	i=0
	while !PortCheck.is_port_open headnode, "4567" 
		Chef::Log.info("****COE-LOG: waiting for first cluster node to become available - sleep 60 seconds - #{i} of 6")
		i+=1
		break if i==6 # break out after waiting 6 intervals
		sleep 60 # sleep for 60 seconds before retry
    end
  end
end

# now let's set the root password only if this is the initial install
execute "Update MySQL root password" do
  command "mysqladmin --user=root --password='' password '#{passwords.root_password}'"
  not_if "test -f /etc/mysql/grants.sql"
end

# setup the debian system user config
template "/etc/mysql/debian.cnf" do
  source "debian.cnf.erb"
  variables(:debian_password => passwords.debian_password)
  owner "root"
  group "root"
  mode 0640
  notifies :restart, "service[mysql]", :immediately if node["percona"]["auto_restart"]

  only_if { node["platform_family"] == "debian" }
end


#####################################
## CONFIGURE ACCESS FOR SST REPLICATION
#####################################
if firstnode
	sstAuth = node["percona"]["cluster"]["wsrep_sst_auth"].split(':')
	sstAuthName = sstAuth[0]
	sstauthPass = sstAuth[1]
	# Create the state transfer user
	execute "add-mysql-user-sstuser" do
		command "/usr/bin/mysql -u root -p#{passwords.root_password} -D mysql -r -B -N -e \"CREATE USER '#{sstAuthName}'@'localhost' IDENTIFIED BY '#{sstauthPass}'\""
		action :run
		#Chef::Log.info('****COE-LOG add-mysql-user-sstuser')
		only_if { `/usr/bin/mysql -u root -p#{passwords.root_password} -D mysql -r -B -N -e \"SELECT COUNT(*) FROM user where User='sstuser' and Host = 'localhost'"`.to_i == 0 }
	end
	# Grant priviledges
	execute "grant-priviledges-to-sstuser" do
		#Chef::Log.info('****COE-LOG grant-priviledges-to-sstuser')
		command "/usr/bin/mysql -u root -p#{passwords.root_password} -D mysql -r -B -N -e \"GRANT RELOAD, LOCK TABLES, REPLICATION CLIENT ON *.* TO '#{sstAuthName}'@'localhost'\""
		action :run
	#DEL    only_if { `/usr/bin/mysql -u root -p#{mysql_password} -D mysql -r -B -N -e \"SELECT COUNT(*) FROM user where User='sstuser' and Host = 'localhost'"`.to_i == 0 }
	end
	# Flush
	execute "flush-mysql-priviledges" do
		#Chef::Log.info('****COE-LOG flush-mysql-priviledges')
		command "/usr/bin/mysql -u root -p#{passwords.root_password} -D mysql -r -B -N -e \"FLUSH PRIVILEGES\""
		action :run
	#DEL    only_if { `/usr/bin/mysql -u root -p#{mysql_password} -D mysql -r -B -N -e \"SELECT COUNT(*) FROM user where User='sstuser' and Host = 'localhost'"`.to_i == 0 }
	end
end
