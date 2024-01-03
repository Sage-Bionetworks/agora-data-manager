# Overview
Agora Data Manager is a tool that loads the JSON files into Agora's document database instances in our AWS environments.

# Purpose
This project allows Agora maintainers to update the Agora database with
new versions of gene data from Synapse.  This is a manually triggered,
self-service update. 

# Execution

![alt text][db_update]

# Worflow

To deploy an updated data version to the Agora development database
1. Increment `data-version` in `data-manifest.json` on the `develop` branch.
2. Commit the change
3. The Github action CI system automatically updates the dev DB


To deploy an updated data version to the Agora staging database:
1. Merge the data-version update from the dev branch to the staging branch.
2. The Github action CI system automatically updates the dev DB

To deploy an updated data version to the Agora production database:
1. Merge the data-version update from the staging branch to the production branch.
2. The Github action CI system automatically updates the dev DB


# Setup

The following secrets need to be setup in Github for the scripts to deploy database updates:

Global secrets:

| Variable             | Description                       | Example                     |
|----------------------|-----------------------------------|-----------------------------|
| SYNAPSE_USERNAME     | The Synapse service user          | syn-service-user            |
| SYNAPSE_PASSWORD     | The Synapse service user password | supersecret                 |


Context specific secrets for each environment that corresponds to a git branch (develop/staging/prod):

| Variable  | Description                 | Example                                                                   |
|-----------|-----------------------------|---------------------------------------------------------------------------|
| DB_HOST   | The database host           | dbcluster-mr0a782pfjnk.cluster-ctcayu3de2lt.us-east-1.docdb.amazonaws.com |
| DB_USER   | The database user           | dbuser                                                                    |
| DB_PASS   | The database password       | supersecret                                                               |


![alt text][github_secrets]



[db_update]: agora-db-update.drawio.png "update diagram"
[github_secrets]: github_secrets.png "github secrets screen"