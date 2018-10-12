#!/bin/bash

set -eu

: ${BUCKET_NAME:?}
: ${STEMCELL_BUCKET_NAME:?} # used to check if current stemcell already exists

stemcell_url() {
  resource="/${STEMCELL_BUCKET_NAME}/${light_stemcell_name}"

  if [ ! -z "$AWS_ACCESS_KEY_ID" ]; then
    expires=$(date +%s)
    expires=$((expires + 30))

    string_to_sign="HEAD\n\n\n${expires}\n${resource}"
    signature=$(echo -en "$string_to_sign" | openssl sha1 -hmac ${AWS_SECRET_ACCESS_KEY} -binary | base64)
    signature=$(python -c "import urllib; print urllib.quote_plus('${signature}')")

    echo -n "https://s3.amazonaws.com${resource}?AWSAccessKeyId=${AWS_ACCESS_KEY_ID}&Expires=${expires}&Signature=${signature}"
  else
    echo -n "https://s3.amazonaws.com${resource}"
  fi
}

# inputs
builder_src="$PWD/builder-src"
stemcell_dir="$PWD/stemcell"

# outputs
light_stemcell_dir="$PWD/light-stemcell"
raw_stemcell_dir="$PWD/raw-stemcell"

echo "Creating light stemcell..."

salt=$(date +%s)
original_stemcell="$(echo ${stemcell_dir}/*.tgz)"
original_stemcell_name="$(basename "${original_stemcell}")"
raw_stemcell_name="$(basename "${original_stemcell}" .tgz)-raw-$salt.tar.gz"
light_stemcell_name="light-${original_stemcell_name}"

echo "Using raw stemcell name: $raw_stemcell_name"

light_stemcell_url="$(stemcell_url)"
set +e
wget --spider "$light_stemcell_url"
if [[ "$?" == "0" ]]; then
  echo "Google light stemcell '$light_stemcell_name' already exists!"
  echo "You can download here: $light_stemcell_url"
  exit 1
fi
set -e

mkdir working_dir
pushd working_dir
  tar xvf "${original_stemcell}"

  raw_stemcell_path="${raw_stemcell_dir}/${raw_stemcell_name}"
  mv image "${raw_stemcell_path}"
  raw_disk_sha1="$(sha1sum ${raw_stemcell_path} | awk '{print $1}')"
  echo -n "${raw_disk_sha1}" > ${raw_stemcell_path}.sha1

  > image
  light_stemcell_sha1=$(sha1sum image | awk '{print $1}')
  stemcell_format="google-light"

  cp stemcell.MF /tmp/stemcell.MF.tmp

  bosh int \
    -o $builder_src/ci/assets/light-stemcell-ops.yml \
    -v "light_stemcell_sha1=$light_stemcell_sha1" \
    -v 'stemcell_formats=["google-light"]' \
    -v "source_url=https://storage.googleapis.com/${BUCKET_NAME}/${raw_stemcell_name}" \
    -v "raw_disk_sha1=${raw_disk_sha1}" \
    /tmp/stemcell.MF.tmp > stemcell.MF

  light_stemcell_path="${light_stemcell_dir}/${light_stemcell_name}"
  tar czvf "${light_stemcell_path}" *
popd
