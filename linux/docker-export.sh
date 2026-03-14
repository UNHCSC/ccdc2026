echo "All docker containers will end up in the current directory in <container>-filesystem-<ISO-time>.tar"

d=$(date -I'minute')


docker ps --format '{{.Names}} {{.ID}} {{.Image}}' | while read -r name id image; do
    docker export $name -o "$name-filesystem-$d.tar"
done;

