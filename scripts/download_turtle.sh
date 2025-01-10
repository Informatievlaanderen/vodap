#!/bin/bash

# a curl version of the OSLO-Hypermedia driven pagination building block
# returning a ntriples file
# 
set -x

URL=$1
FORMAT="application/rdf+xml"
TARGET=$2

startindex=0


# ensure target directory exists
DIR=$(dirname ${TARGET})
mkdir -p ${DIR}

TARGETFILE=$(basename ${TARGET})


#####################################
# process link headers
#####################################
process_link_headers() {

NEXT=$1
LAST=$2


while [ "${NEXT}" != "${LAST}" ] ; do
    curl --retry 5 -D headers -o payload -k -L "${NEXT}"
    rapper -i guess -o turtle payload >> ${TARGET}
    NEXT=`grep next headers |sed "s/^.*<//"  |sed "s/>.*$//" `
    LAST=`grep last headers |sed "s/^.*<//"  |sed "s/>.*$//" `
done

  
}
#####################################
# process hydra 
#####################################
process_hydra() {

NEXT=$1
LAST=$2


while [ "${NEXT}" != "${LAST}" ] ; do
    curl --retry 5 -D headers -o payload -k -L "${NEXT}"
    rapper -i guess payload > NT
    NEXT=`cat NT | grep hydra |grep next |sed "s/^.*Page>//" | sed 's/"//g' | sed -r -e 's/^\s*//' |sed -r -e 's/\s*.$//' `
    LAST=`cat NT | grep hydra |grep last |sed "s/^.*Page>//" | sed 's/"//g' | sed -r -e 's/^\s*//' |sed -r -e 's/\s*.$//' `
    cat NT >> ${TARGET}
done

}

#####################################
# process as if there where many pages 
#####################################
# https://metadata.vlaanderen.be/api/collections/main/items/?f=dcat_ap_vl
# https://metadata.vlaanderen.be/api/collections/main/items/items?startindex=10&limit=10
process_pages() {

BASE=$1
PAGESIZE=$2
STARTPARAM=startindex
PAGESIZEPARAM=limit

i=0
ERR=200
CERR=/tmp/CERR
WKD=/tmp/workspace/


while [ $ERR -lt 400 ] ; do
    URL="${BASE}&${STARTPARAM}=${i}&${PAGESIZEPARAM}=${PAGESIZE}"
    PREFIX="${STARTPARAM}${i}.${PAGESIZEPARAM}${PAGESIZE}."
    echo "process ${URL}" 
    curl -s -w "%{stderr}%{http_code}" --retry 5 -D headers -o payload -k -L "${URL}" &> CERR
    rapper -i guess -o turtle payload > "${WKD}${PREFIX}${TARGETFILE}"
    if [ $? -eq 0 ] ; then 
	    cat "${WKD}${PREFIX}${TARGETFILE}" >> ${TARGET}
	    rm "${WKD}${PREFIX}${TARGETFILE}" 
    fi
    i=$((i+${PAGESIZE}))
    ERR=$(cat CERR )
    echo $ERR

done

}



######################################
# curl
curl -D headers -o payload -k -L "${URL}"

# follow the link headers if present
FIRST=`grep first headers |sed "s/^.*<//"  |sed "s/>.*$//" `
NEXT=`grep next headers |sed "s/^.*<//"  |sed "s/>.*$//" `
LAST=`grep last headers |sed "s/^.*<//"  |sed "s/>.*$//" `


if [ "${FIRST}" != "" -a "${NEXT}" != "" -a "${LAST}" != "" ] ; then
  echo "use link headers"
  rapper -i guess -o turtle payload > ${TARGET}
  process_link_headers ${NEXT} ${LAST}
  exit 0;
fi

rapper -i guess payload > NT


FIRST=`cat NT | grep hydra |grep first |sed "s/^.*Page>//" | sed 's/"//g' | sed -r -e 's/^\s*//' |sed -r -e 's/\s*.$//' `
NEXT=`cat NT | grep hydra |grep next |sed "s/^.*Page>//" | sed 's/"//g' | sed -r -e 's/^\s*//' |sed -r -e 's/\s*.$//' `
LAST=`cat NT | grep hydra |grep last |sed "s/^.*Page>//" | sed 's/"//g' | sed -r -e 's/^\s*//' |sed -r -e 's/\s*.$//' `

if [ "${FIRST}" != "" -a "${NEXT}" != "" -a "${LAST}" != "" ] ; then
  echo "use hydra payload"
  cat NT > ${TARGET}
  process_hydra ${NEXT}  ${LAST}
  exit 0;
fi

echo "no pagination found - try hardcoded pagination"
process_pages ${URL} 50 ${TARGET}

#echo "no pagination found - assume single respons"
#rapper -i guess payload > ${TARGET}
exit 0;
