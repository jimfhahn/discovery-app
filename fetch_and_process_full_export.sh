#!/bin/bash

if [[ "$OSTYPE" == "darwin"* ]]; then
    script_dir="$(dirname "$(stat -f "$0")")"
else
    script_dir="$(dirname "$(readlink -f "$0")")"
fi

job_id=S4741763270003681
set_name=fulltest
sleeptime=300

if [ -z "$1" ]
then
    echo "Usage: fetch_and_process_full_export.sh EXPORT_DIR"
    exit
else
    export_dir="$1"
fi

api_response=""

while ! [[ $api_response =~ "COMPLETED_SUCCESS" ]]; do

    api_response=`wget -q -O- "https://api-na.hosted.exlibrisgroup.com/almaws/v1/conf/jobs/$job_id/instances?limit=1&offset=0&apikey=$ALMA_API_KEY"`

    echo "Waiting $sleeptime seconds before checking job status again..."
    sleep $sleeptime
done

export_name=TODO

now=`date -u +"%Y-%m-%dT%H:%M:%SZ"`

echo "############################################################"
echo "#### Full export ssh transfer and process started at `date`"

echo "Transferring via ssh"
# TODO

mkdir -p "$export_dir/$export_name/processed"
cd "$export_dir/$export_name/processed"
ls ../*.tar.gz | xargs -i tar xf {}
chmod a+r *

cd $script_dir

echo "Running preprocessing tasks"
./preprocess.sh "$export_dir/$export_name" "$set_name"

echo "Running indexing"
./index_solr.sh "$export_dir/$export_name/processed"

echo "#### full export fetch and process ended at `date`"
