#!/bin/bash
set -euo pipefail

# Hold the ECS agent until the data volume is attached and mounted, so the
# task never starts against an empty host path.
systemctl stop ecs || true

echo "ECS_CLUSTER=${cluster_name}" >> /etc/ecs/ecs.config

TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

# Attach the persistent data volume. Retries cover the overlap window during a
# replacement deploy where the old instance still holds the attachment.
for i in $(seq 1 60); do
  if aws ec2 attach-volume --region ${region} --volume-id ${volume_id} --device /dev/xvdf --instance-id "$INSTANCE_ID"; then
    break
  fi
  echo "attach-volume attempt $i failed; retrying in 10s"
  sleep 10
done

# On Nitro instances EBS volumes surface as NVMe devices; resolve by volume id.
VOL_ID_NODASH=$(echo "${volume_id}" | tr -d '-')
DEV=""
for i in $(seq 1 60); do
  CANDIDATE="/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_$VOL_ID_NODASH"
  if [ -e "$CANDIDATE" ]; then
    DEV=$(readlink -f "$CANDIDATE")
    break
  fi
  sleep 5
done
if [ -z "$DEV" ]; then
  echo "data volume never appeared" >&2
  exit 1
fi

# Format ONLY a brand-new volume — an existing filesystem means live SQLite data.
if ! blkid "$DEV"; then
  mkfs.xfs "$DEV"
fi

mkdir -p ${mount_dir}
mount "$DEV" ${mount_dir}

# The data-service container runs as distroless nonroot (uid/gid 65532).
chown 65532:65532 ${mount_dir}

echo "$DEV ${mount_dir} xfs defaults,nofail 0 2" >> /etc/fstab

systemctl enable ecs
# --no-block: cloud-final runs this script, and a blocking start deadlocks
# against cloud-init ordering.
systemctl start --no-block ecs
