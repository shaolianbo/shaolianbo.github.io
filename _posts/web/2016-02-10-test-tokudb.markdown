---
layout: "post"
title: "TokuDB 安装与使用方法总结及其压缩效果测试"
date: "2016-2-10 18:05"
categories:  ["web"]
tag:  ["web", "TokuDB", "数据库"]
---

最近对我维护的监控系统做升级开发，监控数据的统计结果数量剧增，需要每天存储8w~9w条的数据。之前的存储没有压力， 是使用mysql + InnoDB存储的，测了一下，如果不改变存储方法的话，每天会消耗421M磁盘。 实际上那台做存储的机器上只有50G磁盘了， 仅能支持3个月。 因此不得不解决存储的事， 首先想到的是找一个HBase的集群，这样自己也不用担心存储量的问题，不幸的是，目前部门没有。 另一种途径是换一种压缩率高的Mysql存储引擎，TokuDB 是在[手搜](http://m.sohu.com/?v=3)使用的MySQL引擎，主要是使用它存储压缩比高的特性，因此我把一天的模拟数据分别插入InnoDB、MyISAM、TokuDB三种引擎的数据库中，对比磁盘消耗。结果如下：

  |InnoDB |MyISAM |TokuDB  
--|---|---|--
日增量|421M|284M|84M  
50G支持天数|121|180|609  


因为数据只需要存储一年内的就好了，所以决定使用TokuDB

现把TokuDB的安装使用方法总结如下， 还包括计算Mysql数据库磁盘占用量的方法。


#### 什么是Percona?什么是TokuDB

[Percona](https://en.wikipedia.org/wiki/Percona) 是一家数据库咨询、培训、管理公司，而且主要针对Mysql。 它们维护了一个开源Mysql的变种， 名字
叫Percona Server, 比官方MySQL提供更强劲的性能。 [TokuDB](https://en.wikipedia.org/wiki/TokuDB)包含在Percona Server内，作为mysql的
一个存储引擎，高压缩率、高tps。

方便起见，我没单独安装TokuDB, 而是直接完全安装了Percona Service, 代替了原先的Mysql。


#### 安装Percona Server 、TokuDB; 更改数据文件路径

Percona Server 使用yum安装，没有什么好说的，见：[https://www.percona.com/doc/percona-server/5.6/installation/yum_repo.html](https://www.percona.com/doc/percona-server/5.6/installation/yum_repo.html)

Percona Server默认并不启用TokuDB, 若要启用，需要安装完Percona Server后，调用`ps_tokudb_admin`命令， 详见：[https://www.percona.com/doc/percona-server/5.6/tokudb/tokudb_installation.html](https://www.percona.com/doc/percona-server/5.6/tokudb/tokudb_installation.html)

Percona Server默认数据文件目录为/var/lib/mysql/， 配置文件/etc/my.cnf。 如果要改变数据文件目录， 需要先使用命令`mysql_install_db`创建一个mysql数据文件目录，再修改/etc/my.cnf(如果没有，就自己创建)， 添加：

    [mysqld]
    datadir=/opt/mysql/data


#### 计算数据磁盘占用量

如果是测试环境，也就是只有一个数据库在写入的话，直接比较测试前后数据库目录的大小，这是最准确的， 使用`du -h`即可。

除此之外，可以通过mysql内建的information_schema数据库，查看用户数据库的磁盘占用量，但测试证明它和真实的磁盘空间占用空间稍微有出入。 TokuDB的磁盘占用量查看方法和其它引擎的查看方法不同，详见
[https://www.percona.com/blog/2014/10/10/mysql-compression-compressed-and-uncompressed-data-size/](https://www.percona.com/blog/2014/10/10/mysql-compression-compressed-and-uncompressed-data-size/)


#### 关于InnoDB的数据文件

![mysqldatadir](/assets/pic/2016/02/mysqldir.png)

如上图，是一个mysql的data目录， 每个文件夹代表一个数据库，但是并不是数据库的数据都会存在自己的目录内。比如默认所有InnoDB引擎的表数据, 都会存在ibdata1这个文件里, 这是InnoDB表共享的一个文件， 这里有一问题，比如有一个1G磁盘大小的InnoDB数据库表， 当它被删除后，ibdata1这个文件并不会
释放这1G的磁盘空间。 解决方法是innodb_file_per_table这个参数设为1，这样各个InnoBD的表就不会共享一个文件了，而是各存各的，表删后， 磁盘空间也会释放了。

    [mysqld]
    innodb_file_per_table=1

这个问题的讨论，见StackOverflow: [http://stackoverflow.com/questions/3456159/how-to-shrink-purge-ibdata1-file-in-mysql](http://stackoverflow.com/questions/3456159/how-to-shrink-purge-ibdata1-file-in-mysql)
