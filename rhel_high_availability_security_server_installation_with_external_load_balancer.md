# High Availability Security Server with External Load Balancer and Opmonitor

X-Road 7.2.2

High Availability Setup

## Document version history <!-- omit in toc -->


|Release no|Author|Date|Brief summary of changes|
| :- | :- | :- | :- |
|v1.0.0|CamDX Operator|July 2022||
|v2.0.0|CamDX Operator|May 2023|Update support for RHEL 8.7|

## Table of Contents <!-- omit in toc -->

<!-- toc -->
<!-- vim-markdown-toc GFM -->
- [1. Network Diagram](#1-network-diagram)

- [2.	State Replication from Master Security Server to Slaves](#2-state-replication-from-master-security-server-to-slaves)

- [3.	INSTALLATION](#3-installation)

  - [3.1	Prerequisites](#31-prerequisites)

  - [3.2	Database Replication Setup](#32-database-replication-setup)
  
  - [3.3	Data Replication Setup](#33-data-replication-setup)

  - [3.4	Verification](#34-verification)

- [4.	EXTERNAL LOAD BALANCER](#4-external-load-balancer)

  - [4.1	Installation and Configuration](#41-installation-and-configuration)

- [5.	INSTALLING AND CONFIGURING EXTERNAL OPERATIONAL MONITORING](#5-installing-and-configuring-external-operational-monitoring)

  - [5.1	Hardware Requirement](#51-hardware-requirement)

  - [5.2	Configure External Operational Monitoring](#52-configure-external-operational-monitoring)

  - [5.3	Configure Master node for External Operational Monitoring](#53-configure-master-node-for-external-operational-monitoring)

- [6.	CONFIGURATION](#6-configuration)

- [7.	REFERENCES](#7-references)

## 1. Network Diagram
The network diagram below provides an example of a basic Security Server setup. Allowing incoming connections from the Monitoring Security Server on ports 5500/tcp and 5577/tcp is necessary for the CamDX Operator to be able to monitor the ecosystem and provide statistics and support for Members.

![FIGURE 1 – NETWORK DIAGRAM](ansible/img/ha_ss_ext_lb.png)
<p align="center"> FIGURE 1 – NETWORK DIAGRAM </p>

## 2. State Replication from Master Security Server to Slaves

- State Replication from the master to the slaves
- Replicated State: 
  - severconf DB: PostgreSQL streaming replication (Hot standby), 
  - keyconf replication(softtoken & keyconf): rsync+ssh (scheduled),
  - Other server configuration parameters from /etc/xroad/\: rsync+ssh (schedule)
    - db.properties
    - postgresql/\*
    - globalconf/
    - conf.d/node.ini
- Non-replicated State: 
  - messagelog DB
  - OCSP responses from /var/cache/xroad


![img](img/ha_f4.png)

<p align="center"> FIGURE 2 – MASTER SLAVES STATE REPLICATION </p>

## 3. INSTALLATION
### 3.1 Prerequisites
Security Server Master and Slave node must already have package *xroad-securityserver* installed!

In order to properly setup data replication, the slave nodes must be able to connect to:

- The master server using SSH (tcp port 22), and
- The master serverconf database (e.g tcp port 5433)

### 3.2 Database Replication Setup
**3.2.1 Create a Separate PostgreSQL Instance for serverconf Database on Master Node**

*Setting up TLS Certificate for Database Authentication:*
- Generate the Certificate Authority Key and a self-signed Certificate for the root-of-trust
```bash
root@master# openssl req -new -x509 -days 7300 -nodes -sha256 -out ca.crt -keyout ca.key -subj '/O=CamDX/CN=CA'
```
- Generate Keys and Certificates signed by the CA for each PostgreSQL Instance, including the master. Do not use
the CA certificate and key as the database certificate and key
```bash
root@master# openssl req -new -nodes -days 7300 -keyout server.key -out server.csr -subj "/O=CamDX/CN=ss1"

root@master# openssl x509 -req -in server.csr -CAcreateserial -CA ca.crt -CAkey ca.key -days 7300 -out server.crt
```
- Copy the Certificates and Keys
```bash
root@master# mkdir -p -m 0755 /etc/xroad/postgresql
root@master# chmod o+x /etc/xroad
root@master# cp ca.crt server.crt server.key /etc/xroad/postgresql
root@master# chown postgres /etc/xroad/postgresql/*
root@master# chmod 400 /etc/xroad/postgresql/*
```
*Create a new systemctl service unit for the new database.*
```bash
cat <<EOF >/etc/systemd/system/postgresql-serverconf.service 
.include /lib/systemd/system/postgresql.service 
[Service] 
Environment=PGPORT=5433 
Environment=PGDATA=/var/lib/pgsql/serverconf 
EOF
```
*Create a serverconf database and configure SELinux by using the following command:*
```bash
root@master# PGSETUP_INITDB_OPTIONS="--auth-local=peer --auth-host=md5 -E UTF8" postgresql-setup --initdb --unit postgresql-serverconf --port 5433

root@master# semanage port -a -t postgresql_port_t -p tcp 5433
root@master# systemctl enable postgresql-serverconf
```
*Configuring the master instance for replication:*
```bash
root@master# vim /var/lib/pgsql/serverconf/postgresql.conf
```
```bash
ssl = on
ssl_ca_file = '/etc/xroad/postgresql/ca.crt'
ssl_cert_file = '/etc/xroad/postgresql/server.crt'
ssl_key_file = '/etc/xroad/postgresql/server.key'

listen_addresses = '*'
wal_level = hot_standby
max_wal_senders = 3 
wal_keep_segments = 8 
```
```bash
root@master# vim /var/lib/pgsql/serverconf/pg_hba.conf
```
```bash
hostssl replication +slavenode 10.0.10.20/32 cert

#10.0.10.20/32 is the slave node IP
```
```bash
root@master# systemctl start postgresql-serverconf
root@master# sudo -u postgres psql -p 5433 -c "CREATE ROLE slavenode NOLOGIN";
root@master# sudo -u postgres psql -p 5433 -c "CREATE USER "ss2" REPLICATION PASSWORD NULL IN ROLE slavenode";
#This ss2 must match with the /CN in certificate generation in *TLS Certificate for Database Authentication for Slave*
```
```bash
root@master# sudo -u postgres psql -p 5433 -c "CREATE USER serverconf PASSWORD '<Passw0rd>'";
root@master# sudo -u postgres pg_dump -C serverconf | sudo -u postgres psql -p 5433 -f -
root@master# sudo -u postgres psql -p 5432 -c "ALTER DATABASE serverconf RENAME TO serverconf_old";
```
```bash
root@master# firewall-cmd --zone=public --add-port=5433/tcp --permanent
root@master# firewall-cmd --reload
```
```bash
root@master# vim /etc/xroad/db.properties
```
```bash
serverconf.hibernate.connection.url = jdbc:postgresql://127.0.0.1:5433/serverconf
serverconf.hibernate.connection.password = <Passw0rd>
```
*TLS Certificate for Database Authentication for Slave*

- Generate the Certificate Authority Key and Certificate Signing Request, and issue Certificate for Slave node
```bash
root@master# openssl req -new -nodes -days 7300 -keyout server_ss2.key -out server_ss2.csr -subj "/O=CamDX/CN=ss2"
root@master# openssl x509 -req -in server_ss2.csr -CAcreateserial -CA ca.crt -CAkey ca.key -days 7300 -out server_ss2.crt
```

**3.2.2 Create a Separate PostgreSQL Instance for serverconf Database on Slave Node**

*Setting up TLS Certificate for Database Authentication:*
```bash
root@slave# mkdir -p -m 0755 /etc/xroad/postgresql
root@slave# chmod o+x /etc/xroad
```
- Copy certificates and key from Master to Slave
```bash
root@master# scp ca.crt server_ss2.crt server_ss2.key slave@10.0.10.20:/home/slave
#10.0.10.20 is slave node's IP
```
```bash
root@slave# mv ca.crt server_ss2.crt server_ss2.key /etc/xroad/postgresql
root@slave# chown postgres /etc/xroad/postgresql/*
root@slave# chmod 400 /etc/xroad/postgresql/*
```
*Create a serverconf database by using the following command:*
```bash
cat <<EOF >/etc/systemd/system/postgresql-serverconf.service 
.include /lib/systemd/system/postgresql.service 
[Service] 
Environment=PGPORT=5433 
Environment=PGDATA=/var/lib/pgsql/serverconf 
EOF
```
```bash
root@slave# PGSETUP_INITDB_OPTIONS="--auth-local=peer --auth-host=md5 -E UTF8" postgresql-setup --initdb --unit postgresql-serverconf --port 5433
```
```bash
root@slave# semanage port -a -t postgresql_port_t -p tcp 5433
root@slave# systemctl enable postgresql-serverconf
```

*Configuring the slave instance for replication:*
- Clear the Data Directory
```bash
root@slave# rm -rf /var/lib/pgsql/serverconf/*
```
```bash
root@slave# sudo -u postgres PGSSLMODE=verify-ca PGSSLROOTCERT=/etc/xroad/postgresql/ca.crt PGSSLCERT=/etc/xroad/postgresql/server_ss2.crt PGSSLKEY=/etc/xroad/postgresql/server_ss2.key pg_basebackup -h 10.0.10.10 -p 5433 -U ss2 -D /var/lib/pgsql/serverconf/

#do a backup with pg_basebackup and 10.0.10.10 is master node's IP
```
- Create a recovery.conf in that data directory
```bash
root@slave# vim /var/lib/pgsql/serverconf/recovery.conf
```
```bash
standby_mode = 'on'

primary_conninfo = 'host=10.0.10.10 port=5433 user=ss2 sslmode=verify-ca sslcert=/etc/xroad/postgresql/server_ss2.crt sslkey=/etc/xroad/postgresql/server_ss2.key sslrootcert=/etc/xroad/postgresql/ca.crt'

trigger_file = '/var/lib/xroad/postgresql.trigger'
```
```bash
root@slave# chown postgres:postgres /var/lib/pgsql/serverconf/recovery.conf
root@slave# chmod 0600 /var/lib/pgsql/serverconf/recovery.conf
```
Notice that on RHEL, during pg_basebackup the postgresql.conf was copied from the primary node so the WAL sender parameters should be disabled. Also check that listen_addresses is localhost-only.

```bash
root@slave# vim /var/lib/pgsql/serverconf/postgresql.conf
```
```bash
ssl = on
ssl_ca_file = '/etc/xroad/postgresql/ca.crt'
ssl_cert_file = '/etc/xroad/postgresql/server_ss2.crt'
ssl_key_file = '/etc/xroad/postgresql/server_ss2.key'
listen_addresses = 'localhost'

# no need to send WAL logs
# wal_level = minimal
# max_wal_senders = 0
# wal_keep_segments = 0

hot_standby = on
hot_standby_feedback = on
```
```bash
root@slave# vim /var/lib/pgsql/serverconf/pg_hba.conf
```
```bash
# TYPE  DATABASE    USER      ADDRESS       METHOD

# "local" is for Unix domain socket connection only
local   all         all                     peer
# IPv4 local connections:
host    all         all       127.0.0.1/32  md5
# IPv6 local connections:
host    all         all       ::1/128       md5
# Allow replication connections from localhost, by a user with the
# replication privilege.
local   replication all                     peer
host    replication all       127.0.0.1/32  md5
host    replication all       ::1/128       md5
```
SELinux for postgres to access those certificates and key at /etc/xroad/postgresql/
```bash
root@slave# semanage fcontext -a -t postgresql_etc_t "/etc/xroad/postgresql/*"
root@slave# restorecon -v /etc/xroad/postgresql/*
```
Start PostgreSQL serverconf database
```bash
root@slave# systemctl start postgresql-serverconf
```
Update db.properties to point to new serverconf database
```bash
root@slave# vim /etc/xroad/db.properties
```
```bash
serverconf.hibernate.connection.url = jdbc:postgresql://127.0.0.1:5433/serverconf
serverconf.hibernate.connection.password = <Passw0rd>        #this was created on Master node
```

### 3.3 Data Replication Setup
**3.3.1 Setup SSH between slaves and master**

***On slave**, generate the ssh key for the xroad user by using the following command: (**without a passphrase**)*
```bash
root@slave# sudo -i -u xroad
xroad@slave# ssh-keygen -t rsa
```
```bash
Generating public/private rsa key pair.
Enter file in which to save the key (/var/lib/xroad/.ssh/id_rsa):
Created directory '/var/lib/xroad/.ssh'.
Enter passphrase (empty for no passphrase):
Enter same passphrase again:
Your identification has been saved in /var/lib/xroad/.ssh/id_rsa.
Your public key has been saved in /var/lib/xroad/.ssh/id_rsa.pub.
The key fingerprint is:
SHA256:IDwKIFrUlnhgrpMrDBOlCY49ShETZyFoDGFxqXSiNl8 xroad@slave
The key's randomart image is:
+---[RSA 3072]----+
|X@XOo.           |
|X&O+=            |
|@oBo+ .          |
|oX o E .         |
|O + .   S        |
|o+ .             |
|o.               |
|.                |
|                 |
+----[SHA256]-----+
```

*Copy ssh xroad public key to the Master Node for later adding to **/home/xroad-slave/.ssh/authorized_keys***
```bash
xroad@slave# cat /var/lib/xroad/.ssh/id_rsa.pub
```
***On Master**, setup a system user that can read **/etc/xroad** a system user has their password disabled and cannot log in normally*
```bash
root@master# useradd -r -m -g xroad xroad-slave

root@master# mkdir -m 755 -p /home/xroad-slave/.ssh && sudo touch /home/xroad-slave/.ssh/authorized_keys
```
*paste the copied **id_rsa.pub** from slave*
```bash
root@master# vim /home/xroad-slave/.ssh/authorized_keys
```
***On slave**, test ssh to master without password with user **xroad-slave**, and accept key*
```bash
xroad@slave# ssh xroad-slave@10.0.10.10              #this must work without password

The authenticity of host '10.0.10.10 (10.0.10.10)' can't be established.
ECDSA key fingerprint is SHA256:rI3JY5nbPaXYppI1867kiOkh0CyvGgBk8xjQv4Q8WQE.
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added '10.0.10.10' (ECDSA) to the list of known hosts.
```
```bash
xroad-slave@master# exit
xroad@slave# exit
```

*Setup periodic configuration synchronization on the slave node*
- Confirm that rsync is installed on both Master and Slave node
```bash
root@master# yum install rsync -y
```
```bash
root@slave# yum install rsync -y
```
```bash
root@slave# vim /etc/systemd/system/xroad-sync.service
```
```bash
[Unit]
Description=X-Road Sync Task
After=network.target
Before=xroad-proxy.service
Before=xroad-signer.service
Before=xroad-confclient.service
Before=xroad-proxy-ui-api.service

[Service]
User=xroad
Group=xroad
Type=oneshot
Environment=XROAD_USER=xroad-slave
Environment=MASTER=10.0.10.10                 #Master node's IP
ExecStartPre=/usr/bin/test ! -f /var/tmp/xroad/sync-disabled

ExecStart=/usr/bin/rsync -e "ssh -o ConnectTimeout=5 " -aqz --timeout=10 --delete-delay --exclude "/backup.d" --exclude db.properties --exclude "/conf.d/node.ini" --exclude "*.tmp" --exclude "/postgresql" --exclude "/globalconf" --exclude "/gpghome" --delay-updates --log-file=/var/log/xroad/slave-sync.log ${XROAD_USER}@${MASTER}:/etc/xroad/ /etc/xroad/

[Install]
WantedBy=multi-user.target
WantedBy=xroad-proxy.service
```
```bash
root@slave# vim /etc/systemd/system/xroad-sync.timer
```
```bash
[Unit]
Description=Sync X-Road configuration

[Timer]
OnBootSec=60
OnUnitActiveSec=60

[Install]
WantedBy=timers.target
```
Configure SELinux to allow rsync to be run as a systemd service
```bash
root@slave# setsebool -P rsync_client 1
root@slave# setsebool -P rsync_full_access 1
```
```bash
root@slave# systemctl enable xroad-sync.timer xroad-sync.service
root@slave# systemctl start xroad-sync.timer
```
```bash
root@slave# vim /etc/logrotate.d/xroad-slave-sync
```
```bash
/var/log/xroad/slave-sync.log {
  daily
  rotate 7
  missingok
  compress
  su xroad xroad
  nocreate
}
```
**3.3.2 Configure Node Type: (Both Master and Slave)**

*Configure node type **on Master***
```bash
root@master# vim /etc/xroad/conf.d/node.ini
```
```bash
[node]
type=master
```
```bash
root@master# chown xroad:xroad /etc/xroad/conf.d/node.ini
root@master# systemctl start xroad-proxy
```
*Configure node type **on Slave***
```bash
root@slave# vim /etc/xroad/conf.d/node.ini
```
```bash
[node]
type=slave
```
```bash
root@slave# chown xroad:xroad /etc/xroad/conf.d/node.ini
root@slave# systemctl start xroad-proxy
```
### 3.4 Verification
**3.4.1 Verifying rsync+ssh replication:**

To test the configuration file replication, a new file can be added to **/etc/xroad** or **/etc/xroad/signer** on the **master node** and verify it has been replicated to the **slave nodes** in a few minutes. Make sure the file is owned by the group xroad.
```bash
root@master# touch /etc/xroad/test.txt
root@master# chown xroad:xroad /etc/xroad/test.txt
```
Alternatively, check the sync log **/var/log/xroad/slave-sync.log** on the **slave nodes** and verifying its lists successful transfers.
```bash
root@slave# tail /var/log/xroad/slave-sync.log
```
```
2023/06/02 09:52:53 [66760] >f..t...... ssl/internal.p12
2023/06/02 09:52:53 [66760] >f..t...... ssl/proxy-ui-api.crt
2023/06/02 09:52:53 [66760] >f.st...... ssl/proxy-ui-api.key
2023/06/02 09:52:53 [66760] >f..t...... ssl/proxy-ui-api.p12
2023/06/02 09:52:53 [66758] sent 471 bytes  received 10538 bytes  total size 43651
2023/06/02 09:54:03 [66773] receiving file list
2023/06/02 09:54:03 [66775] .d..t...... ./
2023/06/02 09:54:03 [66775] >f+++++++++ test.txt
2023/06/02 09:54:03 [66775] .d..t...... conf.d/
2023/06/02 09:54:03 [66773] sent 187 bytes  received 1183 bytes  total size 43651
```

**3.4.2 Verifying database replication: on Master**

```bash
root@master# sudo -u postgres psql -p 5433 -c "select * from pg_stat_replication;"
```
A successful replication with a slave node could look like this:

| pid  | usesysid | usename  | application_name |  client_addr   | client_hostname | client_port |         backend_start         | backend_xmin |   state   | sent_lsn | write_lsn | flush_lsn | replay_lsn | sync_priority | sync_state |
|------|----------|----------|------------------|----------------|-----------------|-------------|-------------------------------|-----------|-----------|---------------|----------------|----------------|-----------------|---------------|------------|
| 66215 |    16385 | ss2 | walreceiver      | 10.0.10.20 |                 |       60524 | 2023-06-02 09:18:31.237375+07 | 718 | streaming | 0/30002C8     | 0/30002C8      | 0/30002C8      | 0/30002C8       |             0 | async      |



## 4. EXTERNAL LOAD BALANCER
### 4.1 Installation and Configuration
**4.1.1 Installation**

*On another instance for external loadbalancer*
```bash
root@loadbalancer# yum update -y
root@loadbalancer# timedatectl set-timezone Asia/Phnom_Penh
root@loadbalancer# yum install nginx -y
```
**4.1.2 Configuring Passthrough on port 5500, 5577, 8080, and 8443**

In this High Availability Security Server setup with External Load Balancer, please note that the dns record for security server should be resolved to the load balancer for traffic distribution to each servers (It is possible to seperate External and Local Reverse Proxy stationing in different security zone)

DNS: 	ss-dev.company1.com.kh => <ip_of_load_balancer>

Note: By default, xroad-proxy listens for consumer information system connections on ports 8080 (HTTP) and 8443 (HTTPS)

```bash
root@loadbalancer# mkdir /etc/nginx/stream.d
root@loadbalancer# vim /etc/nginx/stream.d/passthrough.conf
```
```bash
stream {

    # Log Format Configuration
    log_format basic '$remote_addr [$time_local] '
                 '$protocol $status $bytes_sent $bytes_received '
                 '$session_time "$upstream_addr" '
                 '"$upstream_bytes_sent" "$upstream_bytes_received" "$upstream_connect_time"';

    # Log File Configuration
    access_log /var/log/nginx/ss-dev.company1.com.kh_access.log basic;
    error_log /var/log/nginx/ss-dev.company1.com.kh_error.log;

    # Replace fqdn_of_ss_master and fqdn_of_ss_slave with master and slave node IP

    # Upstream Configuration for port 5500, 5577, 80, and 443
    upstream camdx_5500 {
        server fqdn_of_ss_master:5500 max_fails=1 fail_timeout=10s;
        server fqdn_of_ss_slave:5500 max_fails=1 fail_timeout=10s;
    }
    upstream camdx_5577 {
        server fqdn_of_ss_master:5577 max_fails=1 fail_timeout=10s;
        server fqdn_of_ss_slave:5577 max_fails=1 fail_timeout=10s;
    }
    upstream camdx_8080 {
        server fqdn_of_ss_master:8080 max_fails=1 fail_timeout=1s;
        server fqdn_of_ss_slave:8080 max_fails=1 fail_timeout=1s;
    }
    upstream camdx_8443 {
        server fqdn_of_ss_master:8443 max_fails=1 fail_timeout=1s;
        server fqdn_of_ss_slave:8443 max_fails=1 fail_timeout=1s;
    }

    # Server Listener
    server {
        listen 5500;
        proxy_pass camdx_5500;
        proxy_next_upstream on;
    }
    server {
        listen 5577;
        proxy_pass camdx_5577;
        proxy_next_upstream on;
    }
    server {
        listen 8080;
        proxy_pass camdx_8080;
        proxy_next_upstream on;
    }
    server {
        listen 8443;
        proxy_pass camdx_8443;
        proxy_next_upstream on;
    }
}
```
*Add to the bottom of **/etc/nginx/nginx.conf**  to include the passthrough configuration file*
```bash
root@loadbalancer# vim /etc/nginx/nginx.conf
```
```bash
include /etc/nginx/stream.d/passthrough.conf;
```
*Remove the default configuration file*
```bash
root@loadbalancer# rm -rf /etc/nginx/sites-enabled/default
```

Test and Reload nginx 
```bash
root@loadbalancer# systemctl start nginx
root@loadbalancer# systemctl enable nginx
```

Allow access on below ports on both master and slave security server:
```bash
root@master# firewall-cmd --zone=public --add-port=5500/tcp --add-port=5577/tcp --add-port=8080/tcp --add-port=8443/tcp --permanent
root@master# firewall-cmd --reload
```
```bash
root@slave# firewall-cmd --zone=public --add-port=5500/tcp --add-port=5577/tcp --add-port=8080/tcp --add-port=8443/tcp --permanent
root@slave# firewall-cmd --reload
```

## 5. INSTALLING AND CONFIGURING EXTERNAL OPERATIONAL MONITORING
### 5.1 Hardware Requirement
- The server’s hardware (motherboard, CPU, network interface cards, storage system) must be supported by Ubuntu in general
- CPU: 2
- RAM: 4GB
- DISK: 100GB
- Network Card: 100 Mbps
- Running Port 2080/tcp (Allow access from Security Servers only)

**Install Security Server Package**
```bash
root@opmonitor# yum update -y
root@opmonitor# timedatectl set-timezone Asia/Phnom_Penh
root@opmonitor# echo LC_ALL=en_US.UTF-8 | tee -a /etc/environment
root@opmonitor# yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm -y

root@opmonitor# rpm --import https://repository.camdx.gov.kh/repository/camdx-anchors/api/gpg/key/0x04194DBF-pub.asc

root@opmonitor# yum-config-manager --add-repo https://repository.camdx.gov.kh/repository/camdx-release-rpm/rhel/8/7.2.2
```
```bash
root@opmonitor# vim /etc/yum.repos.d/repository.camdx.gov.kh_repository_camdx-release-rpm_rhel_8_7.2.2.repo
```
```bash
[repository.camdx.gov.kh_repository_camdx-release-rpm_rhel_8_7.2.2] 
name=created by dnf config-manager from https://repository.camdx.gov.kh/repository/camdx-release-rpm/rhel/8/7.2.2 
baseurl=https://repository.camdx.gov.kh/repository/camdx-release-rpm/rhel/8/7.2.2 
enabled=1 
gpgcheck=0
```
```bash
root@opmonitor# yum update
root@opmonitor# yum install xroad-securityserver
root@opmonitor# yum install xroad-opmonitor
root@opmonitor# systemctl start xroad-proxy

#Stop and disable Services
root@opmonitor# systemctl stop xroad-proxy xroad-proxy-ui-api xroad-monitor
root@opmonitor# systemctl disable xroad-proxy xroad-proxy-ui-api xroad-monitor
```

### 5.2 Configure External Operational Monitoring
```bash
root@opmonitor# vim /etc/xroad/conf.d/local.ini
```
```bash
[op-monitor]
keep-records-for-days = 30
host = 0.0.0.0
```

Download the configuration anchor
- This configuration anchor specifies the URL for opmonitor to download its global configuration information
```bash
root@opmonitor# curl -o /etc/xroad/configuration-anchor.xml https://repository.camdx.gov.kh/repository/camdx-anchors/anchors/CAMBODIA_configuration_anchor.xml
```

```bash
root@opmonitor# chown xroad:xroad /etc/xroad/configuration-anchor.xml
root@opmonitor# systemctl restart xroad-opmonitor
```
Allow access to 2080/tcp:
```bash
root@opmonitor# firewall-cmd --zone=public --add-port=2080/tcp --permanent
root@opmonitor# firewall-cmd --reload
```

### 5.3 Configure Master node for External Operational Monitoring
*On Security Server **Master Node**, we also need to edit a configuration file at **/etc/xroad/conf.d/local.ini***
```bash
root@master# vim /etc/xroad/conf.d/local.ini
```
```bash
[op-monitor]
host = 10.0.10.30              #opmonitor_ip_or_domain_name
```
*Install xroad-addon-proxymonitor & xroad-addon-opmonitoring - on Master*
```bash
root@master# yum install xroad-addon-proxymonitor xroad-addon-opmonitoring -y
root@master# systemctl restart xroad-opmonitor

#Stop and Disable the Local Operation Monitoring Service on Master Node
root@master# systemctl stop xroad-opmonitor
root@master# systemctl disable xroad-opmonitor
```

*Install xroad-addon-proxymonitor & xroad-addon-opmonitoring - on Slave*
```bash
root@master# yum install xroad-addon-proxymonitor xroad-addon-opmonitoring -y
root@master# systemctl restart xroad-opmonitor

#Stop and Disable the Local Operation Monitoring Service on Master Node
root@master# systemctl stop xroad-opmonitor
root@master# systemctl disable xroad-opmonitor
```

## 6. CONFIGURATION

Configure Security Server **Master Node** by following the configuration section in [rhel_standalone_security_server_installation_and_configuration.md](https://github.com/Techo-Startup-Center/CamDX-Documents/blob/main/rhel_standalone_security_server_installation_and_configuration.md#4-configuration)

## 7. REFERENCES

X-Road/ig-xlb_x-road_external_load_balancer_installation_guide.md at camdx-6.23.0 · CamDX/X-Road. (2022). Retrieved 30 May 2022, from <https://github.com/Techo-Startup-Center/CamDX/blob/camdx-6.23.0/doc/Manuals/LoadBalancing/ig-xlb_x-road_external_load_balancer_installation_guide.md>
