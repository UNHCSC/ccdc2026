# Given a running container and a filesystem export from: 
#   docker export <container> -o <filesystem>.tar
# Will replace the given container's filesystem with the 
#   new filesystem
# This WILL NOT recover any data saved in ro mounts, those will have to be saved manually
# 
# Also useful: https://docs.docker.com/engine/storage/volumes/#back-up-restore-or-migrate-data-volumes


if [[ $# -ne 2 ]]; then
    echo "Format ./script <container> <filesystem.tar>"
    exit 1;
fi;

echo "Importing filesystem"

docker cp ./$2 $1:/
docker exec -it $1 tar -xf /$2 -C /