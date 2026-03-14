echo "Allowing ports $@ + 22"

sudo ufw allow 22
for arg in "$@"; do
    sudo ufw allow "$arg"
done;
sudo ufw enable 
sudo ufw status