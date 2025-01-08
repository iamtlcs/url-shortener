ZIP_CREATE_SHORT_URL = create_short_url.zip
ZIP_REDIRECT_URL = redirect_url.zip
CREATE_SHORT_URL_DIR = ./create_short_url
REDIRECT_URL_DIR = ./redirect_url
API_GATEWAY_URL = https://2upsfsr49l.execute-api.ap-southeast-1.amazonaws.com/prod

.PHONY: all zip_create_short_url zip_redirect_url apply_terraform clean

all: zip_create_short_url zip_redirect_url apply_terraform

zip_create_short_url:
	@echo "Zipping create_short_url..."
	cd $(CREATE_SHORT_URL_DIR) && zip -r ../$(ZIP_CREATE_SHORT_URL) .

zip_redirect_url:
	@echo "Zipping redirect_url..."
	cd $(REDIRECT_URL_DIR) && zip -r ../$(ZIP_REDIRECT_URL) .

zip_all: zip_create_short_url zip_redirect_url

update_create_short_url:
	@echo "Updating create_short_url..."
	aws lambda update-function-code --function-name create_short_url --zip-file fileb://$(ZIP_CREATE_SHORT_URL) --no-cli-pager

update_redirect_url:
	@echo "Updating redirect_url..."
	aws lambda update-function-code --function-name redirect_url --zip-file fileb://$(ZIP_REDIRECT_URL) --no-cli-pager

update_all: update_create_short_url update_redirect_url

push_all: zip_all update_all

apply_terraform: zip_all
	@echo "Applying Terraform configuration..."
	terraform init
	terraform apply -auto-approve
	@echo "Terraform configuration applied."
	
print_api_gateway_url:
	@echo "API Gateway URL: $(API_GATEWAY_URL)"

destroy_terraform:
	@echo "Destroying Terraform configuration..."
	terraform destroy -auto-approve

clean:
	@echo "Cleaning up zip files..."
	rm -f $(ZIP_CREATE_SHORT_URL) $(ZIP_REDIRECT_URL)

testCreateApi:
	curl -X POST $(API_GATEWAY_URL)/create \
		-H "Content-Type: application/json" \
		-d '{"url": "https://www.example.com", "suffix": "H3LL0"}'

testRedirectApi:
	curl -X GET $(API_GATEWAY_URL)/H3LL0

testAll: testCreateApi testRedirectApi