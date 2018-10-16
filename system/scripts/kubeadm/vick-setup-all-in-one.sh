#!/bin/bash
# ------------------------------------------------------------------------
#
# Copyright 2018 WSO2, Inc. (http://wso2.com)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License
#
# ------------------------------------------------------------------------

function deploy_mysql_server () {
    download_location=$1
    #Create folders required by the mysql PVC
    if [ -d /mnt/mysql ]; then
        sudo mv /mnt/mysql "/mnt/mysql.$(date +%s)"
    fi
    sudo mkdir -p /mnt/mysql
    #Change the folder ownership to mysql server user.
    sudo chown 999:999 /mnt/mysql

    kubectl create configmap mysql-dbscripts --from-file=${download_location}/mysql/dbscripts/ -n vick-system
    kubectl apply -f ${download_location}/mysql-persistent-volumes-local.yaml -n vick-system
    kubectl apply -f ${download_location}/mysql-persistent-volume-claim.yaml -n vick-system
    kubectl apply -f ${download_location}/mysql-deployment.yaml -n vick-system
    #Wait till the mysql deployment availability
    kubectl wait deployment/wso2apim-with-analytics-mysql-deployment --for condition=available --timeout=6000s -n vick-system
    kubectl apply -f ${download_location}/mysql-service.yaml -n vick-system
}

function deploy_global_gw () {
    download_location=$1
    #Create folders required by the APIM GW PVC
    if [ -d /mnt/apim_repository_deployment_server ]; then
        sudo mv /mnt/apim_repository_deployment_server "/mnt/apim_repository_deployment_server.$(date +%s)"
    fi
    #Create folders required by the APIM PVC
    sudo mkdir -p /mnt/apim_repository_deployment_server
    sudo chown 802:802 /mnt/apim_repository_deployment_server

    #Create the gw config maps
    kubectl create configmap gw-conf --from-file=${download_location}/apim-configs/gw -n vick-system
    kubectl create configmap gw-conf-datasources --from-file=${download_location}/apim-configs/gw/datasources/ -n vick-system
    #Create KM config maps
    kubectl create configmap conf-identity --from-file=${download_location}/apim-configs/gw/identity -n vick-system
    kubectl create configmap apim-template --from-file=${download_location}/apim-configs/gw/resources/api_templates -n vick-system
    kubectl create configmap apim-tomcat --from-file=${download_location}/apim-configs/gw/tomcat -n vick-system
    kubectl create configmap apim-security --from-file=${download_location}/apim-configs/gw/security -n vick-system
    #Create apim local volumes and volume claims
    kubectl apply -f ${download_location}/vick-apim-persistent-volumes-local.yaml -n vick-system
    kubectl apply -f ${download_location}/vick-apim-persistent-volume-claim-local.yaml -n vick-system
    #Create gateway deployment and the service
    kubectl apply -f ${download_location}/vick-apim-gw.yaml -n vick-system
     #Wait till the gateway deployment availability
    kubectl wait deployment/gateway --for condition=available --timeout=6000s -n vick-system
    #Create gateway ingress
    kubectl apply -f ${download_location}/vick-apim-gw-ingress.yaml -n vick-system
}

function deploy_sp_dashboard_worker () {
    download_location=$1
    #Create SP worker configmaps
    kubectl create configmap sp-worker-siddhi --from-file==${download_location}/sp-worker/siddhi -n vick-system
    kubectl create configmap sp-worker-conf --from-file==${download_location}/sp-worker/conf -n vick-system
    kubectl create configmap sp-worker-bin --from-file==${download_location}/sp-worker/bin -n vick-system
    #Create SP worker deployment
    kubectl apply -f vick-sp-worker-deployment.yaml -n vick-system
    kubectl apply -f vick-sp-worker-service.yaml -n vick-system
    #Create SP dashboard configmaps
    kubectl create configmap sp-dashboard-conf --from-file==${download_location}/status-dashboard/conf -n vick-system
    #kubectl create configmap sp-worker-bin --from-file=sp-worker/bin -n vick-system
    #Create SP status dashboard deployment
    kubectl apply -f vick-sp-dashboard-deployment.yaml -n vick-system
    kubectl apply -f vick-sp-dashboard-service.yaml -n vick-system
    #Create SP dashboard ingress
    kubectl apply -f vick-sp-dashboard-ingress.yaml -n vick-system
}
function init_control_plane () {
    download_location=$1
    #Setup VICK namespace, create service account and the docker registry credentials
    kubectl apply -f ${download_location}/vick-ns-init.yaml

    HOST_NAME=$(hostname | tr '[:upper:]' '[:lower:]')
    #label the node
    kubectl label nodes $HOST_NAME disk=local

    #Create credentials for docker.wso2.com
    #kubectl create secret docker-registry wso2creds --docker-server=docker.wso2.com --docker-username=$DOCKER_REG_USER --docker-password=$DOCKER_REG_PASSWD --docker-email=$DOCKER_REG_USER_EMAIL -n vick-system
}

function deploy_istio () {
    download_location=$1
    wget https://github.com/istio/istio/releases/download/1.0.2/istio-1.0.2-linux.tar.gz
    tar -xzvf istio-1.0.2-linux.tar.gz

    ISTIO_HOME=istio-1.0.2
    export PATH=$ISTIO_HOME/bin:$PATH
    kubectl apply -f $ISTIO_HOME/install/kubernetes/helm/istio/templates/crds.yaml
    #kubectl apply -f $ISTIO_HOME/install/kubernetes/istio-demo.yaml
    #kubectl apply -f $ISTIO_HOME/install/kubernetes/istio-demo-auth.yaml
    kubectl apply -f ${download_location}/istio-demo-vick.yaml
    kubectl wait deployment/istio-pilot --for condition=available --timeout=6000s -n istio-system
    #Enabling Istio injection
    kubectl label namespace default istio-injection=enabled
}

function deploy_vick_crds () {
    download_location=$1
    #Install VICK crds
    kubectl apply -f ${download_location}/vick.yaml
}

function create_artifact_folder () {
 tmp_folder=$1
 if [ -d $tmp_folder ]; then
        mv $tmp_folder ${tmp_folder}.$(date +%s)
    fi

    mkdir ${tmp_folder}
}
function download_vick_artifacts () {

    base_url=$1
    download_path=$2
    yaml_list=("$@")

    for file_path in "${yaml_list[@]}"
    do
      dir_name=""
      if [[ $file_path =~ / ]]; then
        dir_name=${file_path%/*}
      fi
      wget "$base_url/$file_path" -P "$download_path/$dir_name" -a vick-setup.log
    done
}

#-----------------------------------------------------------------------------------------------------------------------

control_plane_base_url="https://raw.githubusercontent.com/wso2/product-vick/master/system/control-plane/global"

control_plane_yaml=(
    "mysql-deployment.yaml"
    "mysql-persistent-volume-claim.yaml"
    "mysql-persistent-volumes-local.yaml"
    "mysql-persistent-volumes.yaml"
    "mysql-service.yaml"
    "nfs-deployment.yaml"
    "nfs-persistent-volume-claim.yaml"
    "nfs-persistent-volumes-local.yaml"
    "nfs-server-service.yaml"
    "vick-apim-gw-ingress.yaml"
    "vick-apim-gw.yaml"
    "vick-apim-persistent-volume-claim-local.yaml"
    "vick-apim-persistent-volume-claim.yaml"
    "vick-apim-persistent-volumes-local.yaml"
    "vick-apim-persistent-volumes.yaml"
    "vick-apim-pub-store-ingress.yaml"
    "vick-apim-pub-store.yaml"
    "vick-ns-init.yaml"
    "vick-sp-dashboard-deployment.yaml"
    "vick-sp-dashboard-ingress.yaml"
    "vick-sp-dashboard-service.yaml"
    "vick-sp-persistent-volumes.yaml"
    "vick-sp-worker-deployment.yaml"
    "vick-sp-worker-service.yaml"
    "apim-configs/gw/datasources/master-datasources.xml"
    "apim-configs/gw/user-mgt.xml"
    "apim-configs/gw/identity/identity.xml"
    "apim-configs/gw/tomcat/catalina-server.xml"
    "apim-configs/gw/carbon.xml"
    "apim-configs/gw/security/Owasp.CsrfGuard.Carbon.properties"
    "apim-configs/gw/registry.xml"
    "apim-configs/gw/resources/api_templates/velocity_template.xml"
    "apim-configs/gw/api-manager.xml"
    "apim-configs/gw/log4j.properties"
    "apim-configs/pub-store/datasources/master-datasources.xml"
    "apim-configs/pub-store/user-mgt.xml"
    "apim-configs/pub-store/identity/identity.xml"
    "apim-configs/pub-store/carbon.xml"
    "apim-configs/pub-store/registry.xml"
    "apim-configs/pub-store/resources/api_templates/velocity_template.xml"
    "apim-configs/pub-store/api-manager.xml"
    "apim-configs/pub-store/log4j.properties"
    "sp-worker/bin/carbon.sh"
    "sp-worker/siddhi/tracer-app.siddhi"
    "sp-worker/siddhi/telemetry-app.siddhi"
    "sp-worker/conf/deployment.yaml"
    "status-dashboard//conf/deployment.yaml"
    "mysql/dbscripts/init.sql"
)

crd_base_url="https://raw.githubusercontent.com/wso2/product-vick/master/build/target"

crd_yaml=("vick.yaml")

istio_base_url="https://raw.githubusercontent.com/wso2/product-vick/master/system/scripts/kubeadm"
istio_yaml=("istio-demo-vick.yaml")

download_path="tmp-wso2"

#-----------------------------------------------------------------------------------------------------------------------
#Create temporary foldr to download vick artifacts
create_artifact_folder $download_path

echo "Downloading vick artifacts"

download_vick_artifacts $control_plane_base_url $download_path "${control_plane_yaml[@]}"

download_vick_artifacts $crd_base_url  $download_path "${crd_yaml[@]}"

download_vick_artifacts $istio_base_url $download_path "${istio_yaml[@]}"

#Init control plane
echo "Creating vick-system namespace and the service account"

init_control_plane $download_path

read -p "Do you want to deploy MySQL server in to vick-system namespace [Y/n]: " install_mysql

if [ $install_mysql == "Y" ]; then
    deploy_mysql_server $download_path
fi

echo "Deploying the control plane API Manager"

deploy_global_gw $download_path

echo "Deploying SP"

deploy_sp_dashboard_worker $download_path

echo "Deploying Istio"

deploy_istio $download_path

echo "Deploy vick crds"

deploy_vick_crds $download_path