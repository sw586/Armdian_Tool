#!/bin/bash
# ###########################  armdian系统优化脚本  ##################
# 测试脚本命令：执行System_Optimization_Tool.sh文件并将执行日志写入log.txt
# sudo chmod u+x /root/System_Optimization_Tool.sh
# sudo  /root/System_Optimization_Tool.sh > /root/log.txt 2>&1

# 安装常用软件
apt install sudo -y
# 安装中文语言包
sudo apt-get install -y locales-all
# ###########################  1-设置时区为中国  ##################
sudo timedatectl set-timezone Asia/Shanghai

# ###########################  2-修改更新源-清华源  ##################
# 修改Armbian 软件仓库镜像为清华源
sudo sed -i.bak 's#http://apt.armbian.com#https://mirrors.tuna.tsinghua.edu.cn/armbian#g' /etc/apt/sources.list.d/armbian.list
# Debian Buster 以上版本默认支持 HTTPS 源。如果遇到无法拉取 HTTPS 源的情况，请先使用 HTTP 源并安装
sudo apt install apt-transport-https ca-certificates -y
# 判断如果是debian12则修改为清华源的debian12软件仓库镜像源
if [ "$(lsb_release -is)" == "Debian" ] && [ "$(lsb_release -rs)" == "12" ]; then
cp /etc/apt/sources.list /etc/apt/sources.list.bak
cat > /etc/apt/sources.list << EOF
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security bookworm-security main contrib non-free non-free-firmware
EOF
fi
apt update -y
export DEBIAN_FRONTEND=noninteractive
apt list --upgradable
# 脚本文件中使用 DEBIAN_FRONTEND=noninteractive 环境变量来实现在执行 apt upgrade -y 时静默选择 no 并继续执行
apt upgrade -yq


# ###########################  3-Debian 双栈网络时开启 IPv4 优先  ##################
sed -i 's/#precedence ::ffff:0:0\/96  100/precedence ::ffff:0:0\/96  100/' /etc/gai.conf

# ###########################  4-挂载SD卡和U盘  ##################
# 挂载SD卡
mkdir /sd
mount /dev/mmcblk0p1 /sd
# 挂载U盘
mkdir /upan
mount /dev/sda1 /upan
# 开机自动挂载
echo '/dev/mmcblk0p1 /sd ext4 defaults 0 0' | sudo tee -a /etc/fstab

# ###########################  5-搭建Samba服务器,共享目录/upan,用户:root,密码：sw63828  ##################
sudo apt-get install samba -y
sudo chmod 777 /upan
# 该命令将使用 cat 命令将指定的内容追加到 /etc/samba/smb.conf 文件的末尾
cat >> /etc/samba/smb.conf << EOF
[upan]
path = /upan/
read only = no
browsable = yes
valid users = root
create mask = 0775
directory mask = 0775
EOF
# 该命令将使用 echo 和管道命令 | 将密码传递给 smbpasswd 命令，以添加名为 root 的 Samba 用户并设置其密码为 sw63828
echo -ne "sw63828\nsw63828\n" | sudo smbpasswd -a root
# 重启 Samba 服务
sudo service smbd restart

# ###########################  6-配置github ssh权限  ##################
#该命令将使用 ssh-keygen 命令生成一对新的 ed25519 类型的 SSH 密钥，并使用 -f 选项指定密钥文件的位置/root/.ssh/id_ed25519，
# 使用 -N 选项指定空密码。这样，在执行脚本时，系统将不会提示您输入任何信息，而是自动执行密钥生成过程。
ssh-keygen -t ed25519 -C "sw586@126.com" -f /root/.ssh/id_ed25519 -N ""
# 在后台启动 ssh 代理
eval "$(ssh-agent -s)"
# 将 SSH 私钥添加到 ssh-agent
ssh-add ~/.ssh/id_ed25519

# 通过System_Optimization_Tool.sh脚本输出/root/.ssh/id_ed25519.pub内容，并且输出内容“将 SSH 公钥添加到 GitHub 上的
# 帐户https://github.com/settings/keys”，在输入yes后再执行命令
cat /root/.ssh/id_ed25519.pub
echo "将 SSH 公钥添加到 GitHub 上的帐户 https://github.com/settings/keys"
read -p "是否已经添加好了，添加好就开始继续执行了？(yes/no): " answer
if [ "$answer" == "yes" ]; then
  #输入yes后执行的命令
  #执行ssh -T git@github.com如果返回Hi sw586! You've successfully authenticated, but GitHub does not provide shell access.
  # 则执行ping 127.0.0.1否则输出“检测失败，请检测！”
    output=$(ssh -T git@github.com 2>&1)
    if [[ $output == *"Hi sw586! You've successfully authenticated, but GitHub does not provide shell access."* ]]; then
        #开始拉取仓库
        # 检查 /sd/wankeyun 目录是否存在
        if [ -d /sd/wankeyun ]; then
            # 删除 /sd/wankeyun 目录
            rm -rf /sd/wankeyun
        fi
        # 克隆仓库
        git clone git@github.com:sw586/wankeyun.git /sd/wankeyun

        chmod -R u+x /sd/wankeyun/
        # 运行功能
        /sd/wankeyun/run.sh
        # 添加开机启动
        # 在 /etc/rc.local 文件中添加您指定的命令。如果您的系统上没有 /etc/rc.local 文件，脚本会输出 “未找到 /etc/rc.local 文件”
        if [ -f /etc/rc.local ]; then
            # 备份原始文件
            cp /etc/rc.local /etc/rc.local.bak
            # 在 exit 0 前插入命令
            sed -i '/^exit 0/i sudo mount /dev/sda1 /upan' /etc/rc.local
            sed -i '/^exit 0/i chmod -R u+x /sd/wankeyun/' /etc/rc.local
            sed -i '/^exit 0/i /sd/wankeyun/rc_local_run.sh' /etc/rc.local
        else
            echo "未找到 /etc/rc.local 文件"
        fi
        # 添加定时任务
        (crontab -l 2>/dev/null; echo "*/5 * * * * /sd/wankeyun/update-ip.sh") | crontab -
        # 输出完成信息
        echo -e "\033[32m============= 系统优化完成 =========\033[0m"
        echo -e "\033[32m                                  \033[0m"
        echo -e "\033[32m 1-设置时区为中国 \033[0m"
        echo -e "\033[32m 2-修改更新源-清华源 \033[0m"
        echo -e "\033[32m 3-Debian 双栈网络时开启 IPv4 优先 \033[0m"
        echo -e "\033[32m 4-挂载SD卡/sd，U盘/upan \033[0m"
        echo -e "\033[32m 5-搭建Samba服务器：访问地址:\\onecloud,共享目录:/upan,用户:root,密码,sw63828 \033[0m"
        echo -e "\033[32m 6-配置github ssh权限,仓库：https://github.com/sw586/wankeyun \033[0m"
        echo -e "\033[32m                                  \033[0m"
    else
        echo "检测失败，请检测！"
    fi
fi