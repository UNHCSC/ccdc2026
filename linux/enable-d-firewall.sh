echo "Allowing ports $@ + 22 tcp"


sudo firewall-cmd --permanent --add-port=22/tcp
for arg in "$@"; do
    sudo firewall-cmd --zone=public --permanent --add-port="$arg"/udp
    sudo firewall-cmd --zone=public --permanent --add-port="$arg"/tcp
done;

sudo firewall-cmd --reload
sudo firewall-cmd --list-all