#!/bin/bash

exec_hooks() {
    local dir=$1
    if [ -d $dir ]
    then
        echo " == Running $(basename $dir) scripts"
        for x in $dir/*
        do
            if [ -x $x ]
            then
               echo " ==== Running $(basename $x)"
               . $x
            else
                echo skipping $(basename $x)
            fi
        done
        echo " == Done $(basename $dir) scripts"
    fi
}

update_image() {
    local image="$1"
    if [ "${image}" != "null" ]
    then
        IFS='/' read -a image_parts <<< "$image"
        len=${#image_parts[@]}
        if [ $len == 2 ]
        then
            image_parts=("docker.io" "${image_parts[@]}")
        fi
        if [ "${image_registry}" != "null" ]
        then
            image_parts[0]="${image_registry}"
        fi
        if [ "${image_org}" != "null" ]
        then
            image_parts[1]="${image_org}"
        fi
    else
        if [ "${image_registry}" != "null" ]
        then
            image_parts[0]="${image_registry}"
        fi
        if [ "${image_org}" != "null" ]
        then
            image_parts[1]="${image_org}"
        fi
        image_parts[2]=$2:$3
    fi
    image=$(IFS='/' ; echo "${image_parts[*]}")
    echo "${image}"
}

script_dir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
base_dir=$(cd "${script_dir}/.." && pwd)

if [ $# -gt 0 ]
then
   filename=$1
   if [ -f $filename ] 
   then 
       configfile=$filename
   else
       if [ -f $base_dir/$filename ] 
       then
           configfile=$base_dir/$filename
       else
           if  [ -f $base_dir/config/$filename ]
           then
               configfile=$base_dir/config/$filename
           fi
       fi
   fi
else
    configfile=""   
fi

if [ ! "$configfile" == "" ] 
then
    echo "Config file: $configfile"

    # expose an extension point for running before main 'build' processing
    exec_hooks $script_dir/pre_build.d

    build_dir="${base_dir}/build"
    if [ -z $ASSETS_DIR ]
    then
        assets_dir="${base_dir}/assets"
    else
        assets_dir=$ASSETS_DIR
    fi

    mkdir -p ${assets_dir}
    mkdir -p ${build_dir}

    rm $build_dir/image_list > /dev/null 2>&1 


    REPO_LIST=""
    INDEX_LIST=""
        
    image_org=$(yq r ${configfile} image-org)
    image_registry=$(yq r ${configfile} image-registry)
    nginx_image_name=$(yq r ${configfile} nginx-image-name)
    
    if [ "${image_org}" != "null" ] ||  [ "${image_registry}" != "null" ]
    then
        echo "Retrieving and modifying all the assets"
        export BUILD_ALL=true
        export BUILD=true
        export prefetch_dir="${base_dir}/build/prefetch"
        mkdir -p ${prefetch_dir}
        mkdir -p ${build_dir}/index-src
    else
        echo "Not retrieving or modifying any assets"
    fi

    # Set the default image_org and image_registry values if they 
    # have not been set in the config file
    if [ "${image_org}" == "null" ]
    then
            image_org="appsody"
    fi

    if [ "${image_registry}" == "null" ]
    then
            image_registry="docker.io"
    fi
    
    # count the number of stacks in the index file
    num_stacks=$(yq r ${configfile} stacks[*].name | wc -l)
    if [ $num_stacks -gt 0 ] 
    then
        for ((stack_count=0;stack_count<$num_stacks;stack_count++)); 
        do
            stack_name=$(yq r ${configfile} stacks[$stack_count].name)
            if [ ! -z $BUILD ] && [ $BUILD == true ]
            then
                mkdir -p $base_dir/$stack_name
            fi
            
            REPO_LIST+="${stack_name} "
            
            echo "Creating consolidated index for $stack_name"

            index_file_temp=$assets_dir/$stack_name-index.yaml
            echo "apiVersion: v2" > $index_file_temp
            echo "stacks:" >> $index_file_temp
            
            num_urls=$(yq r ${configfile} stacks[$stack_count].repos[*].url | wc -l)
            
            for ((url_count=0;url_count<$num_urls;url_count++)); 
            do
                url=$(yq r ${configfile} stacks[$stack_count].repos[$url_count].url)
                fetched_index_file=$(basename $url)
                INDEX_LIST+="${url} "
                echo "== fetching $url"
                (curl -s -L ${url} -o $build_dir/$fetched_index_file)

                echo "== Adding stacks from index $url"

                # check if we have any included stacks
                declare -a included
                included_stacks=$(yq r ${configfile} stacks[$stack_count].repos[$url_count].include)
                if [ ! "${included_stacks}" == "null" ]
                then
                    num_included=$(yq r ${configfile} stacks[$stack_count].repos[$url_count].include | wc -l)
                    for ((included_count=0;included_count<$num_included;included_count++));
                    do
                        included=("${included[@]}" "$(yq r ${configfile} stacks[$stack_count].repos[$url_count].include[$included_count]) ")
                    done
                fi

                # check if we have any excluded stacks
                declare -a excluded
                excluded_stacks=$(yq r ${configfile} stacks[$stack_count].repos[$url_count].exclude)
                if [ ! "${excluded_stacks}" == "null" ]
                then
                    num_excluded=$(yq r ${configfile} stacks[$stack_count].repos[$url_count].exclude | wc -l)
                    for ((excluded_count=0;excluded_count<$num_excluded;excluded_count++));
                    do
                        excluded=("${excluded[@]}" "$(yq r ${configfile} stacks[$stack_count].repos[$url_count].exclude[$excluded_count]) ")
                    done
                fi
                
                # count the stacks within the index
                num_index_stacks=$(yq r $build_dir/$fetched_index_file stacks[*].id | wc -l)
                     
                all_stacks=$build_dir/all_stacks.yaml
                one_stack=$build_dir/one_stack.yaml

                # setup a yaml with just the stack info 
                # and new yaml with everything but stacks
                yq r $build_dir/$fetched_index_file stacks | yq p - stacks > $all_stacks

                stack_added="false"
                  	   
                for ((index_stack_count=0;index_stack_count<$num_index_stacks;index_stack_count++));
                do
                    stack_id=$(yq r ${build_dir}/${fetched_index_file} stacks[$index_stack_count].id)
                    stack_version=$(yq r ${build_dir}/${fetched_index_file} stacks[$index_stack_count].version)
                    
                    # check to see if stack is included
                    if [ "${included}" == "" ] || [[ " ${included[@]} " =~ " ${stack_id} " ]]
                    then
                        add_stack_to_index=true
                        # check to see if stack is exncluded (if we have no include)
                        if [[ " ${excluded[@]} " =~ " ${stack_id} " ]]
                        then
                            add_stack_to_index=false
                            echo "==== Excluding stack $stack_id $stack_version "
                        fi
                    else
                        echo "==== Excluding stack $stack_id $stack_version "
                        add_stack_to_index=false
                    fi    
                    
                    if [ $add_stack_to_index == true ]
                    then
                        yq r $all_stacks stacks.[$index_stack_count] > $one_stack
                    
                        # check if stack has already been added to consolidated index
                        num_added_stacks=$(yq r $index_file_temp stacks[*].id | wc -l)
                        for ((added_stack_count=0;added_stack_count<$num_added_stacks;added_stack_count++));
                        do
                            added_stack_id=$(yq r $index_file_temp stacks[$added_stack_count].id)
                            added_stack_version=$(yq r $index_file_temp stacks[$added_stack_count].version)
                            if [ "${stack_id}" == "${added_stack_id}" ]
                            then
                                if [ "${stack_version}" == "${added_stack_version}" ]
                                then
                                    stack_added="true"
                                fi
                            fi
                        done
                    
                        if [ "${stack_added}" == "true" ]
                        then
                            # if already added then log warning message
                            echo "==== ERROR - stack $stack_id $stack_version already added to index"
                        else
                            # if not already added then add to consolidated index
                            echo "==== Adding stack $stack_id $stack_version"
                            yq p -i $one_stack stacks.[+] 
                            if [ ! -z $BUILD ] && [ $BUILD == true ]
                            then
                                image=$(update_image $(yq r $one_stack stacks[0].image) $(yq r $one_stack stacks[0].id) $(yq r $one_stack stacks[0].version))
                                yq w -i $one_stack stacks[0].image $image
                            fi
                            yq m -a -i $index_file_temp $one_stack
                        
                        fi
                    
                        if [ ! -z $BUILD ] && [ $BUILD == true ]
                        then
                            for x in $(cat $one_stack | grep -E 'src:' )
                            do
                                if [ $x != 'src:' ] && [ $x != '""' ]
                                then
                                    filename=$(basename $x)
                                    if [ ! -f $prefetch_dir/$filename ]
                                    then
                                        echo "====== Downloading $prefetch_dir/$filename" 
                                        curl -s -L $x -o $prefetch_dir/$filename
                                    fi
                                fi
                            done

                            for x in $(cat $one_stack | grep -E 'url:' )
                            do
                                if [ $x != 'url:' ]
                                then
                                    filename=$(basename $x)
                                    if [ ! -f $prefetch_dir/$filename ]
                                    then
                                        echo "====== Downloading $prefetch_dir/$filename" 
                                        curl -s -L $x -o $prefetch_dir/$filename
                                    fi

                                    echo "======== Re-packaging $prefetch_dir/$filename"
                                    mkdir -p $build_dir/template

                                    tar -xzf $prefetch_dir/$filename -C $build_dir/template > /dev/null 2>&1            
                                    if [ -f $build_dir/template/.appsody-config.yaml ]
                                    then 
                                        image=$(update_image $(yq r $build_dir/template/.appsody-config.yaml stack))
                                        yq w -i $build_dir/template/.appsody-config.yaml stack $image
                                    fi
                                    tar -czf $prefetch_dir/$filename -C $build_dir/template .

                                    rm -fr $build_dir/template
                                fi
                            done
                        fi
                    fi
                done

                if [ ! -z $BUILD ] && [ $BUILD == true ]
                then
                    index_src=$build_dir/index-src/$(basename "$index_file_temp")
                    sed -e "s|http.*:/.*/|{{EXTERNAL_URL}}/|" $index_file_temp > $index_src
                fi

                if [ "$CODEWIND_INDEX" == "true" ]
                then
                    upper_stack_name=$(tr '[:lower:]' '[:upper:]' <<< ${stack_name:0:1})$(tr '[:upper:]' '[:lower:]' <<< ${stack_name:1})
                    python3 $script_dir/create_codewind_index.py -n ${upper_stack_name} -f $index_file_temp
    
                    if [ -d ${build_dir}/index-src ]
                    then
                        # iterate over each repo
                        for codewind_file in $assets_dir/*.json
                        do
                            # flat json used by static appsody-index for codewind
                            index_src=$build_dir/index-src/$(basename "$codewind_file")

                            sed -e "s|http.*/.*/|{{EXTERNAL_URL}}/|" $codewind_file > $index_src
                        done
                    fi
                fi

                if [ -f  $all_stacks ]
                then
                    rm -f $all_stacks
                fi
                if [ -f  $one_stack ]
                then
                    rm -f $one_stack
                fi
                if [ -f $build_dir/$fetched_index_file ]
                then
                    rm -f $build_dir/$fetched_index_file
                fi
            done
        done
    fi

    # expose an extension point for running after main 'build' processing
    exec_hooks $script_dir/post_build.d
else
    echo "A config file needs to be specified. Please run using: "
    echo "./scripts/hub_build.sh <config_filename>"
fi
