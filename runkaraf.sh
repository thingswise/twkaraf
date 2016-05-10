#!/dumb-init /bin/bash
debug=${DEBUG:-0}

if [ $debug -ne 0 ]; then
  set -x
fi

java_min_mem=${JAVA_MIN_MEM:-128m}
java_max_mem=${JAVA_MAX_MEM:-512m}
wd=${JAVA_WORKDIR:-.}
jvmopts=${JVM_OPTS:-}
archive=${APP_ARCHIVE:-}
http_proxy_host=${HTTP_PROXY:-}
http_proxy_port=${HTTP_PROXY_PORT:-3128}
http_noproxy_host=${HTTP_NOPROXY_HOST:-127.0.0.1,localhost,10.*.*.*,172.17.42.1}

export EXTRA_JAVA_OPTS="$jvmopts"

# In case HTTP Proxy is being provided, enable this configuration for both
# Maven and Java
if [ ! -z $http_proxy_host ]; then
  # Set up proxy
  EXTRA_JAVA_OPTS="-Dhttp.proxyHost=$http_proxy_host -Dhttp.proxyPort=$http_proxy_port -Dhttp.nonProxyHosts=$http_noproxy_host $EXTRA_JAVA_OPTS"
  mkdir -p /.m2/conf
  cat > /.m2/conf/settings.xml << EOF
  <settings>
    <proxies>
      <proxy>
        <id>proxy</id>
        <active>true</active>
        <protocol>http</protocol>
        <host>$http_proxy_host</host>
        <port>$http_proxy_port</port>
        <nonProxyHosts>$http_noproxy_host</nonProxyHosts>
      </proxy>
    </proxies>
  </settings>
EOF
fi

echo "Starting karaf..."
# Look up the karaf dist zip in the directory ${archive}
if [ ! -z $archive ]; then
  echo "Listing archives at ${archive}..."
  zip=$(ls -t $archive|head -1)
  if [ ! -z $zip ]; then
    echo "Newest one is: $zip"
    main_dir=$wd/.dist
    echo "Unpacking in ${main_dir}..."
    (rm -rf $main_dir; mkdir -p $main_dir && cd $main_dir && unzip $archive/$zip) || exit 3
  else
    echo "[WARNING] Cannot find binary distribution archive to unpack... continuing"
  fi
else
  echo "[WARNING] Binary distribution directory not specified... continuing"
fi

function update_bundle_repos() {
  repo_list=(${REPOS//;/ })
  for repo in "${repo_list[@]}"; do
    tgz=$(ls -t $repo|head -1)
    if [ ! -z $tgz ]; then
      main_dir=$REPO_DST
      (mkdir -p $main_dir && cd $main_dir && tar xf $repo/$tgz --keep-newer-files 2>/dev/null)
    fi
  done
}

function update_bundle_repos_loop() {
  while true; do
    update_bundle_repos
    sleep 15
  done
}

echo "[INFO] Forcing update of the bundle repositories"
update_bundle_repos

echo "[INFO] Starting regular bundle repository updates"
update_bundle_repos_loop &

echo "[INFO] Starting karaf runtime"
# Pass some configuration parameters via environmental variables to the
# executed process (bin/karaf)

# Extra java options below (also some are coming with $EXTRA_JAVA_OPTS)
export JAVA_MIN_MEM=$java_min_mem
export JAVA_MAX_MEM=$java_max_mem
# Don't run forever loop inside karaf script, just exec the java process
export KARAF_EXEC=exec
# Specify the Maven configuration directory = /.m2
export M2_HOME=/.m2

cd $wd/.dist/* && exec bin/karaf server 
