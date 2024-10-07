terraform import azurerm_resource_group.rg  /subscriptions/27c83813-916e-49fa-8d2a-d35332fc8ca4/resourceGroups/igor_candidate

az vm list-skus --location eastus --resource-type virtualMachines --zone --all --output table

az vm image list --all --publisher="Canonical" --offer="UbuntuServer"


docker build -t app.py .
docker tag app.py igoracr2bcloud.azurecr.io/app.py
docker push igoracr2bcloud.azurecr.io/app.py


<!-- az login
az acr login --name igoracr2bcloud

docker pull mcr.microsoft.com/mcr/hello-world

docker tag mcr.microsoft.com/mcr/hello-world igoracr2bcloud.azurecr.io/samples/hello-world

docker push igoracr2bcloud.azurecr.io/samples/hello-world -->