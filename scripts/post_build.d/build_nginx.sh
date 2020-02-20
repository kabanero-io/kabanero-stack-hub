#!/bin/bash

image_build() {
    local cmd="docker build"
    if [ "$USE_BUILDAH" == "true" ]; then
        cmd="buildah bud"
    fi

    if ! ${cmd} $@
    then
      echo "Failed building image"
      exit 1
    fi
}

if [ ! -z $BUILD ] && [ $BUILD == true ]
then
    if [ -z "$INDEX_IMAGE" ]
    then
        export INDEX_IMAGE=kabanero-index
    fi

    if [ -z "$INDEX_VERSION" ]
    then
        export INDEX_VERSION=SNAPSHOT
    fi

    NGINX_IMAGE=nginx-ubi
    echo "BUILDING: $NGINX_IMAGE"
    if image_build \
        -t $NGINX_IMAGE \
        -f $script_dir/nginx-ubi/Dockerfile $script_dir
    then
        echo "created $NGINX_IMAGE"
    else
        >&2 echo -e "failed building $NGINX_IMAGE"
        exit 1
    fi

    nginx_arg=
    if [ -n "$NGINX_IMAGE" ]
    then
        nginx_arg="--build-arg NGINX_IMAGE=$NGINX_IMAGE"
    fi

    if [ "${nginx_image_name}" == "null" ]
    then
        nginx_image_name="repo-index"
    fi

    echo "BUILDING: $image_org/${nginx_image_name}:${INDEX_VERSION}"
    if image_build \
        $nginx_arg \
        -t $image_registry/$image_org/${nginx_image_name} \
        -t $image_registry/$image_org/${nginx_image_name}:${INDEX_VERSION} \
        -f $script_dir/nginx/Dockerfile $base_dir
    then
        echo "$image_registry/$image_org/${nginx_image_name}" >> $build_dir/image_list
        echo "$image_registry/$image_org/${nginx_image_name}:${INDEX_VERSION}" >> $build_dir/image_list
        echo "created $image_registry/$image_org/${nginx_image_name}:${INDEX_VERSION}"
    else
        >&2 echo -e "failed building $image_registry/$image_org/${nginx_image_name}:${INDEX_VERSION}"
        exit 1
    fi
fi