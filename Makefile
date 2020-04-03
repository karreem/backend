##############################################
# WARNING : THIS FILE SHOULDN'T BE TOUCHED   #
#    FOR ENVIRONNEMENT CONFIGURATION         #
# CONFIGURABLE VARIABLES SHOULD BE OVERRIDED #
# IN THE 'artifacts' FILE, AS NOT COMMITTED  #
##############################################

SHELL=/bin/bash
export DEBIAN_FRONTEND=noninteractive
export USE_TTY := $(shell test -t 1 && USE_TTY="-t")
#matchID default exposition port
export APP_GROUP=matchID
export APP=backend
export APP_PATH=$(shell pwd)
export PORT=8081
export BACKEND_PORT=8081
export TIMEOUT=30

#matchID default paths
export BACKEND := $(shell pwd)
export FRONTEND=${BACKEND}/../frontend
export UPLOAD=${BACKEND}/upload
export PROJECTS=${BACKEND}/projects
export EXAMPLES=${BACKEND}/../examples
export TUTORIAL=${BACKEND}/../tutorial
export MODELS=${BACKEND}/models
export LOG=${BACKEND}/log
export COMPOSE_HTTP_TIMEOUT=120
export DOCKER_USERNAME=$(shell echo ${APP_GROUP} | tr '[:upper:]' '[:lower:]')
export DC_DIR=${BACKEND}/docker-components
export DC_FILE=${DC_DIR}/docker-compose
export DC_PREFIX := $(shell echo ${APP_GROUP} | tr '[:upper:]' '[:lower:]')
export DC_IMAGE_NAME=${DC_PREFIX}-${APP}
export DC_NETWORK=${DC_PREFIX}
export DC_NETWORK_OPT=
export DC_BUILD_ARGS = --pull --no-cache
export GIT_ROOT=https://github.com/matchid-project
export GIT_ORIGIN=origin
export GIT_BRANCH=dev
export GIT_TOOLS=tools

export API_SECRET_KEY:=$(shell cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1 | sed 's/^/\*/;s/\(....\)/\1:/;s/$$/!/;s/\n//')
export ADMIN_PASSWORD:=$(shell cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1 | sed 's/^/\*/;s/\(....\)/\1:/;s/$$/!/;s/\n//' )
export ADMIN_PASSWORD_HASH:=$(shell echo -n ${ADMIN_PASSWORD} | sha384sum | sed 's/\s*\-.*//')
export POSTGRES_PASSWORD=matchid

export CRED_TEMPLATE=./creds.yml
export CRED_FILE=conf/security/creds.yml

# backup dir
export BACKUP_DIR=${BACKEND}/backup

# s3 conf
# s3 conf has to be stored in two ways :
# classic way (.aws/config and .aws/credentials) for s3 backups
# to use within matchid backend, you have to add credential as env variables and declare configuration in a s3 connector
# 	export aws_access_key_id=XXXXXXXXXXXXXXXXX
# 	export aws_secret_access_key=XXXXXXXXXXXXXXXXXXXXXXXXXXX
export S3_BUCKET=$(shell echo ${APP_GROUP} | tr '[:upper:]' '[:lower:]')
export AWS=${BACKEND}/aws

# elasticsearch defaut configuration
export ES_NODES = 3		# elasticsearch number of nodes
export ES_SWARM_NODE_NUMBER = 2		# elasticsearch number of nodes
export ES_MEM = 1024m		# elasticsearch : memory of each node
export ES_VERSION = 7.6.1
export ES_DATA = ${BACKEND}/esdata
export ES_THREADS = 2
export ES_MAX_TRIES = 3
export ES_CHUNK = 500
export ES_BACKUP_FILE := $(shell echo esdata_`date +"%Y%m%d"`.tar)
export ES_BACKUP_FILE_SNAR = esdata.snar

dummy		    := $(shell touch artifacts)
include ./artifacts

tag                 := $(shell git describe --tags | sed 's/-.*//')
version 			:= $(shell cat tagfiles.version | xargs -I '{}' find {} -type f -not -name '*.tar.gz'  | sort | xargs cat | sha1sum - | sed 's/\(......\).*/\1/')
export APP_VERSION =  ${tag}-${version}

commit 				= ${APP_VERSION}
lastcommit          := $(shell touch .lastcommit && cat .lastcommit)
commit-frontend     := $(shell (cd ${FRONTEND} 2> /dev/null) && git rev-parse HEAD | cut -c1-8)
lastcommit-frontend := $(shell (cat ${FRONTEND}/.lastcommit 2>&1) )
date                := $(shell date -I)
id                  := $(shell cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)

vm_max_count		:= $(shell cat /etc/sysctl.conf | egrep vm.max_map_count\s*=\s*262144 && echo true)

PG := 'postgres'
DC := 'docker-compose'
include /etc/os-release


version:
	@echo ${APP_GROUP} ${APP} ${APP_VERSION}

clean-secrets:
	rm ${CRED_FILE}

register-secrets: config
ifeq ("$(wildcard ${CRED_FILE})","")
	@echo WARNING new ADMIN_PASSWORD is ${ADMIN_PASSWORD}
	@envsubst < ${CRED_TEMPLATE} > ${CRED_FILE}
endif

config:
	# this proc relies on matchid/tools and works both local and remote
	@sudo apt-get install make -yq
	@if [ -z "${TOOLS_PATH}" ];then\
		git clone ${GIT_ROOT}/${GIT_TOOLS};\
		make -C ${APP_PATH}/${GIT_TOOLS} config ${MAKEOVERRIDES};\
	else\
		ln -s ${TOOLS_PATH} ${APP_PATH}/${GIT_TOOLS};\
	fi
	cp artifacts ${APP_PATH}/${GIT_TOOLS}/
	@ln -s ${APP_PATH}/${GIT_TOOLS}/aws ${APP_PATH}/aws
	@touch config

config-clean:
	@rm -rf tools aws config

docker-clean: stop
	docker container rm matchid-build-front matchid-nginx elasticsearch postgres kibana

clean: frontend-clean config-clean

network-stop:
	docker network rm ${DC_NETWORK}

network: config
	@docker network create ${DC_NETWORK_OPT} ${DC_NETWORK} 2> /dev/null; true

elasticsearch-stop:
	@echo docker-compose down matchID elasticsearch
ifeq "$(ES_NODES)" "1"
	@${DC} -f ${DC_FILE}-elasticsearch-phonetic.yml down
else
	@${DC} -f ${DC_FILE}-elasticsearch-huge.yml down
endif

elasticsearch2-stop:
	@${DC} -f ${DC_FILE}-elasticsearch-huge-remote.yml down

elasticsearch-backup: elasticsearch-stop backup-dir
	@echo taring ${ES_DATA} to ${BACKUP_DIR}/${ES_BACKUP_FILE}
	@cd $$(dirname ${ES_DATA}) && sudo tar --create --file=${BACKUP_DIR}/${ES_BACKUP_FILE} --listed-incremental=${BACKUP_DIR}/${ES_BACKUP_FILE_SNAR} $$(basename ${ES_DATA})

elasticsearch-restore: elasticsearch-stop backup-dir
	@if [ -d "$(ES_DATA)" ] ; then (echo purgin ${ES_DATA} && sudo rm -rf ${ES_DATA} && echo purge done) ; fi
	@if [ ! -f "${BACKUP_DIR}/${ES_BACKUP_FILE}" ] ; then (echo no such archive "${BACKUP_DIR}/${ES_BACKUP_FILE}" && exit 1);fi
	@echo restoring from ${BACKUP_DIR}/${ES_BACKUP_FILE} to ${ES_DATA} && \
	 cd $$(dirname ${ES_DATA}) && \
	 sudo tar --extract --listed-incremental=/dev/null --file ${BACKUP_DIR}/${ES_BACKUP_FILE} && \
	 echo backup restored

elasticsearch-s3-push:
	@if [ ! -f "${BACKUP_DIR}/${ES_BACKUP_FILE}" ] ; then (echo no archive to push: "${BACKUP_DIR}/${ES_BACKUP_FILE}" && exit 1);fi
	@${AWS} s3 cp ${BACKUP_DIR}/${ES_BACKUP_FILE} s3://${S3_BUCKET}/${ES_BACKUP_FILE}
	@${AWS} s3 cp ${BACKUP_DIR}/${ES_BACKUP_FILE_SNAR} s3://${S3_BUCKET}/${ES_BACKUP_FILE_SNAR}

elasticsearch-s3-pull: backup-dir
	@echo pulling s3://${S3_BUCKET}/${ES_BACKUP_FILE}
	@${AWS} s3 cp s3://${S3_BUCKET}/${ES_BACKUP_FILE} ${BACKUP_DIR}/${ES_BACKUP_FILE}

backup-dir:
	@if [ ! -d "$(BACKUP_DIR)" ] ; then mkdir -p $(BACKUP_DIR) ; fi

vm_max:
ifeq ("$(vm_max_count)", "")
	@echo updating vm.max_map_count $(vm_max_count) to 262144
	sudo sysctl -w vm.max_map_count=262144
endif

elasticsearch: network vm_max
	@echo docker-compose up matchID elasticsearch with ${ES_NODES} nodes
	@cat ${DC_FILE}-elasticsearch.yml | sed "s/%M/${ES_MEM}/g" > ${DC_FILE}-elasticsearch-huge.yml
	@(if [ ! -d ${ES_DATA}/node1 ]; then sudo mkdir -p ${ES_DATA}/node1 ; sudo chmod g+rw ${ES_DATA}/node1/.; sudo chown 1000:1000 ${ES_DATA}/node1/.; fi)
	@(i=$(ES_NODES); while [ $${i} -gt 1 ]; \
		do \
			if [ ! -d ${ES_DATA}/node$$i ]; then (echo ${ES_DATA}/node$$i && sudo mkdir -p ${ES_DATA}/node$$i && sudo chmod g+rw ${ES_DATA}/node$$i/. && sudo chown 1000:1000 ${ES_DATA}/node$$i/.); fi; \
		cat ${DC_FILE}-elasticsearch-node.yml | sed "s/%N/$$i/g;s/%MM/${ES_MEM}/g;s/%M/${ES_MEM}/g" >> ${DC_FILE}-elasticsearch-huge.yml; \
		i=`expr $$i - 1`; \
	done;\
	true)
	${DC} -f ${DC_FILE}-elasticsearch-huge.yml up -d

elasticsearch2:
	@echo docker-compose up matchID elasticsearch with ${ES_NODES} nodes
	@cat ${DC_FILE}-elasticsearch.yml | head -8 > ${DC_FILE}-elasticsearch-huge-remote.yml
	@(i=$$(( $(ES_NODES) * $(ES_SWARM_NODE_NUMBER) ));j=$$(( $(ES_NODES) * $(ES_SWARM_NODE_NUMBER) - $(ES_NODES))); while [ $${i} -gt $${j} ]; \
	        do \
	              if [ ! -d ${ES_DATA}/node$$i ]; then (echo ${ES_DATA}/node$$i && sudo mkdir -p ${ES_DATA}/node$$i && sudo chmod g+rw ${ES_DATA}/node$$i/. && sudo chown 1000:1000 ${ES_DATA}/node$$i/.); fi; \
	              cat ${DC_FILE}-elasticsearch-node.yml | sed "s/%N/$$i/g;s/%MM/${ES_MEM}/g;s/%M/${ES_MEM}/g" | egrep -v 'depends_on|- elasticsearch' >> ${DC_FILE}-elasticsearch-huge-remote.yml; \
	              i=`expr $$i - 1`; \
	 	done;\
	true)
	${DC} -f ${DC_FILE}-elasticsearch-huge-remote.yml up -d

kibana-stop:
	${DC} -f ${DC_FILE}-kibana.yml down
kibana: network
ifeq ("$(wildcard ${BACKEND}/kibana)","")
	sudo mkdir -p ${BACKEND}/kibana && sudo chmod g+rw ${BACKEND}/kibana/. && sudo chown 1000:1000 ${BACKEND}/kibana/.
endif
	${DC} -f ${DC_FILE}-kibana.yml up -d

postgres-stop:
	${DC} -f ${DC_FILE}-${PG}.yml down
postgres: network
	${DC} -f ${DC_FILE}-${PG}.yml up -d
	@sleep 2 && docker exec ${DC_PREFIX}-postgres psql -U postgres -c "CREATE EXTENSION IF NOT EXISTS fuzzystrmatch"

backend-stop:
	${DC} down

backend-prep:
ifeq ("$(wildcard ${UPLOAD})","")
	@sudo mkdir -p ${UPLOAD}
endif
ifeq ("$(wildcard ${PROJECTS})","")
	@sudo mkdir -p ${PROJECTS}
endif
ifeq ("$(wildcard ${MODELS})","")
	@sudo mkdir -p ${PROJECTS}
endif

backend-dev: network register-secrets backend-prep
	if [ -f docker-compose-local.yml ];then\
		DC_LOCAL="-f docker-compose-local.yml";\
	fi;\
	export BACKEND_ENV=development;\
	export DC_POSTFIX="-dev";\
	if [ "${commit}" != "${lastcommit}" ];then\
		echo building matchID backend after new commit;\
		${DC} build;\
		echo "${commit}" > ${BACKEND}/.lastcommit;\
	fi;\
	${DC} -f docker-compose.yml -f docker-compose-dev.yml $$DC_LOCAL up -d

backend-check-build:
	@if [ -f docker-compose-local.yml ];then\
		DC_LOCAL="-f docker-compose-local.yml";\
	fi;\
	export BACKEND_ENV=production;\
	if [ "${commit}" != "${lastcommit}" ];then\
		echo building ${APP_GROUP} ${APP} for dev after new commit;\
		${DC} build $$DC_LOCAL;\
		echo "${commit}" > ${BACKEND}/.lastcommit;\
	fi;\
	${DC} -f docker-compose.yml $$DC_LOCAL config -q

backend-docker-pull:
	@(\
		(docker pull ${DOCKER_USERNAME}/${DC_PREFIX}-${APP}:${APP_VERSION} > /dev/null 2>&1)\
		&& echo docker successfully pulled && (echo "${commit}" > ${BACKEND}/.lastcommit) \
	) || echo "${DOCKER_USERNAME}/${DC_PREFIX}-${APP}:${APP_VERSION} not found on Docker Hub build, using local"

backend-build: backend-prep register-secrets backend-check-build backend-docker-pull
	@if [ -f docker-compose-local.yml ];then\
		DC_LOCAL="-f docker-compose-local.yml";\
	fi;\
	export BACKEND_ENV=production;\
	if [ "${commit}" != "${lastcommit}" ];then\
		echo building ${APP_GROUP} ${APP} after new commit;\
		${DC} build ${DC_BUILD_ARGS};\
		echo "${commit}" > ${BACKEND}/.lastcommit;\
	fi;
	@docker tag ${DOCKER_USERNAME}/${DC_PREFIX}-${APP}:${APP_VERSION} ${DOCKER_USERNAME}/${DC_PREFIX}-${APP}:latest

backend: network
	@if [ -f docker-compose-local.yml ];then\
		DC_LOCAL="-f docker-compose-local.yml";\
	fi;\
	export BACKEND_ENV=production;\
	${DC} -f docker-compose.yml $$DC_LOCAL up -d

backend-docker-check: config
	@make -C ${APP_PATH}/${GIT_TOOLS} docker-check DC_IMAGE_NAME=${DC_IMAGE_NAME} APP_VERSION=${APP_VERSION} GIT_BRANCH=${GIT_BRANCH} ${MAKEOVERRIDES}

backend-docker-push:
	@make -C ${APP_PATH}/${GIT_TOOLS} docker-push DC_IMAGE_NAME=${DC_IMAGE_NAME} APP_VERSION=${APP_VERSION} ${MAKEOVERRIDES}

frontend-clean:
	@sudo rm -rf ${FRONTEND}/dist

frontend-download:
ifeq ("$(wildcard ${FRONTEND})","")
	@echo downloading frontend code
	@mkdir -p ${FRONTEND}
	@cd ${FRONTEND}; git clone https://github.com/matchID-project/frontend . #2> /dev/null; true
endif

frontend-update:
	@cd ${FRONTEND}; git pull ${GIT_ORIGIN} ${GIT_BRANCH}

backend-update:
	@cd ${BACKEND}; git pull ${GIT_ORIGIN} ${GIT_BRANCH}

update: frontend-update backend-update

frontend-dev:
ifneq "$(commit-frontend)" "$(lastcommit-frontend)"
	@echo docker-compose up matchID frontend for dev after new commit
	${DC} -f ${DC_FILE}-dev-frontend.yml up --build -d
	@echo "${commit-frontend}" > ${FRONTEND}/.lastcommit
else
	@echo docker-compose up matchID frontend for dev
	${DC} -f  ${DC_FILE}-dev-frontend.yml up -d
endif

frontend-dev-stop:
	${DC} -f ${DC_FILE}-dev-frontend.yml down

dev: network frontend-stop backend elasticsearch postgres frontend-dev

dev-stop: backend-stop kibana-stop elasticsearch-stop postgres-stop frontend-dev-stop newtork-stop

frontend-build: network frontend-download
ifneq "$(commit-frontend)" "$(lastcommit-frontend)"
	@echo building matchID frontend after new commit
	@make clean
	@sudo mkdir -p ${FRONTEND}/dist
	${DC} -f ${DC_FILE}-build-frontend.yml up --build
	@echo "${commit-frontend}" > ${FRONTEND}/.lastcommit
endif

frontend-stop:
	${DC} -f ${DC_FILE}-run-frontend.yml down

frontend: frontend-build
	@echo docker-compose up matchID frontend
	${DC} -f ${DC_FILE}-run-frontend.yml up -d

stop: backend-stop elasticsearch-stop kibana-stop postgres-stop
	@echo all components stopped

start-all: start postgres
	@sleep 2 && echo all components started, please enter following command to supervise:
	@echo tail log/docker-*.log

start: frontend-build elasticsearch postgres backend frontend-stop frontend
	@sleep 2 && docker-compose logs

up: start

down: stop

restart: down up

logs: backend
	@docker logs ${DC_PREFIX}-${APP}

example-download:
	@echo downloading example code
	@mkdir -p ${EXAMPLES}
	@cd ${EXAMPLES}; git clone https://github.com/matchID-project/examples . ; true
	@mv projects _${date}_${id}_projects 2> /dev/null; true
	@mv upload _${date}_${id}_upload 2> /dev/null; true
	@ln -s ${EXAMPLES}/projects ${BACKEND}/projects
	@ln -s ${EXAMPLES}/data ${BACKEND}/upload

wait-elasticsearch: elasticsearch
	@timeout=${TIMEOUT} ; ret=1 ; until [ "$$timeout" -le 0 -o "$$ret" -eq "0"  ] ; do (docker exec -i ${USE_TTY} ${DC_PREFIX}-elasticsearch curl -s --fail -XGET localhost:9200/_cat/indices > /dev/null) ; ret=$$? ; if [ "$$ret" -ne "0" ] ; then echo "waiting for elasticsearch to start $$timeout" ; fi ; ((timeout--)); sleep 1 ; done ; exit $$ret

wait-backend: backend
	@timeout=${TIMEOUT} ; ret=1 ; until [ "$$timeout" -le 0 -o "$$ret" -eq "0"  ] ; do (docker exec -i ${USE_TTY} ${DC_PREFIX}-backend curl -s --fail -XGET localhost:${BACKEND_PORT}/matchID/api/v0/ > /dev/null) ; ret=$$? ; if [ "$$ret" -ne "0" ] ; then echo "waiting for backend to start $$timeout" ; fi ; ((timeout--)); sleep 1 ; done ; exit $$ret

recipe-run: wait-backend
	docker exec -i ${USE_TTY} ${DC_PREFIX}-backend curl -s -XPUT http://localhost:${PORT}/matchID/api/v0/recipes/${RECIPE}/run && echo ${RECIPE} run
