#!/bin/bash
set -x
set -e

results_dir="${RESULTS_DIR:-/tmp/results}"

function waitForResources {
    available=false
    max_retries=60
    sleep_seconds=10
    RESOURCE=$1
    NAMESPACE=$2
    for i in $(seq 1 $max_retries)
    do
    if [[ ! $(kubectl wait --for=condition=available ${RESOURCE} --all --namespace ${NAMESPACE}) ]]; then
        sleep ${sleep_seconds}
    else
        available=true
        break
    fi
    done
    
    echo "$available"
}

# saveResults prepares the results for handoff to the Sonobuoy worker.
# See: https://github.com/vmware-tanzu/sonobuoy/blob/master/docs/plugins.md
saveResults() {
    cd ${results_dir}

    # Sonobuoy worker expects a tar file.
	tar czf results.tar.gz *

	# Signal to the worker that we are done and where to find the results.
	printf ${results_dir}/results.tar.gz > ${results_dir}/done
}

# Ensure that we tell the Sonobuoy worker we are done regardless of results.
trap saveResults EXIT

# Login with service principal
az login --service-principal \
  -u ${CLIENT_ID} \
  -p ${CLIENT_SECRET} \
  --tenant ${TENANT_ID}

# Wait for resources in ARC ns
waitSuccessArc="$(waitForResources deployment azure-arc)"
if [ "${waitSuccessArc}" == false ]; then
    echo "deployment is not avilable in namespace - azure-arc"
    exit 1
fi

az extension add --name k8s-extension

az k8s-extension create \
    --cluster-name $CLUSTER_NAME \
    --resource-group $RESOURCE_GROUP \
    --cluster-type connectedClusters \
    --extension-type Microsoft.openservicemesh \
    --subscription $SUBSCRIPTION_ID \
    --scope cluster \
    --release-train staging \
    --name osm \
    --release-namespace $OSM_ARC_RELEASE_NAMESPACE \
    --version $OSM_ARC_VERSION

# Wait for resources in osm-arc release ns
waitSuccessArc="$(waitForResources deployment $OSM_ARC_RELEASE_NAMESPACE)"
if [ "${waitSuccessArc}" == false ]; then
    echo "deployment is not avilable in namespace - $OSM_ARC_RELEASE_NAMESPACE"
    exit 1
fi

export UPSTREAM_REPO="https://github.com/openservicemesh/osm"

git clone -b v${OSM_ARC_VERSION} $UPSTREAM_REPO
cd osm

export CTR_REGISTRY="openservicemesh"
export CTR_TAG=v${OSM_ARC_VERSION}

go test ./tests/e2e -test.v -ginkgo.v -ginkgo.progress -test.timeout 60m -installType=NoInstall -OsmNamespace=$OSM_ARC_RELEASE_NAMESPACE > /tmp/results/results.xml
