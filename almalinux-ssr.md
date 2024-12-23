Almalinux 9 
关闭NetworkManager
systemctl disable NetworkManager-wait-online.service

添加BBR支持
modprobe tcp_bbr
echo "tcp_bbr" | sudo tee --append /etc/modules-load.d/modules.conf
执行
echo "net.core.default_qdisc=fq" | sudo tee --append /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee --append /etc/sysctl.conf
保存生效
sudo sysctl -p
执行
sysctl net.ipv4.tcp_available_congestion_control
sysctl net.ipv4.tcp_congestion_control

实例1：从远处复制文件到本地目录
$scp xxxxx@40.xx.xxx.xxx:/home/xxxmin/xx.sh /home/xxx/
安装软件包
yum -y install wget chkconfig net-tools iptables-services chkconfig
下载Python2.7
wget https://www.python.org/ftp/python/2.7.18/Python-2.7.18.tgz
tar -zxvf Python-2.7.18.tgz
cd Python-2.7.18
./configure --prefix=/usr/bin/python2.7
make
make install
系统自带了python版本，我们需要为新安装的版本添加一个软链#
cp /usr/local/bin/python2.7 /usr/bin/
systemctl daemon-reload
