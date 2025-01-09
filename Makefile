ZIP_CREATE_SHORT_URL = create_short_url.zip
ZIP_REDIRECT_URL = redirect_url.zip
CREATE_SHORT_URL_DIR = ./create_short_url
REDIRECT_URL_DIR = ./redirect_url

.PHONY: all zip_create_short_url zip_redirect_url apply_terraform clean testApi

all: zip_create_short_url zip_redirect_url apply_terraform

zip_create_short_url:
	if [ -f $(ZIP_CREATE_SHORT_URL) ]; then rm $(ZIP_CREATE_SHORT_URL); fi
	@echo "Zipping create_short_url..."
	cd $(CREATE_SHORT_URL_DIR) && pip install -r requirements.txt -t . && zip -r ../$(ZIP_CREATE_SHORT_URL) . -x "venv/*"

zip_redirect_url:
	if [ -f $(ZIP_REDIRECT_URL) ]; then rm $(ZIP_REDIRECT_URL); fi
	@echo "Zipping redirect_url..."
	cd $(REDIRECT_URL_DIR) && zip -r ../$(ZIP_REDIRECT_URL) . -x "venv/*"

zip_all: zip_create_short_url zip_redirect_url

update_create_short_url: zip_create_short_url
	@echo "Updating create_short_url..."
	aws lambda update-function-code --function-name create_short_url --zip-file fileb://$(ZIP_CREATE_SHORT_URL) --no-cli-pager

update_redirect_url: zip_redirect_url
	@echo "Updating redirect_url..."
	aws lambda update-function-code --function-name redirect_url --zip-file fileb://$(ZIP_REDIRECT_URL) --no-cli-pager

update_all: update_create_short_url update_redirect_url

push_all: zip_all update_all

apply_terraform: zip_all
	@echo "Applying Terraform configuration..."
	terraform init
	terraform apply -auto-approve
	@echo "Terraform configuration applied."
	

destroy_terraform:
	@echo "Destroying Terraform configuration..."
	terraform destroy -auto-approve

clean:
	@echo "Cleaning up zip files..."
	rm -f $(ZIP_CREATE_SHORT_URL) $(ZIP_REDIRECT_URL)


testApi:
	@echo "Testing create API..."
	curl -X POST $(shell terraform output -raw api_gateway_invoke_url)/create \
		-H "Content-Type: application/json" \
		-d '{"url": "https://www.example.com", "suffix": "H3LL0"}'

testNotUrl:
	@echo "Testing create API with invalid URL..."
	curl -X POST $(shell terraform output -raw api_gateway_invoke_url)/create \
		-H "Content-Type: application/json" \
		-d '{"url": "example.com", "suffix": "H3LL0"}'