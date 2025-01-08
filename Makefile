ZIP_CREATE_SHORT_URL = create_short_url.zip
ZIP_REDIRECT_URL = redirect_url.zip
CREATE_SHORT_URL_DIR = ./create_short_url
REDIRECT_URL_DIR = ./redirect_url
API_GATEWAY_URL = https://r0awlrl3o8.execute-api.ap-southeast-1.amazonaws.com/prod

.PHONY: all zip_create_short_url zip_redirect_url apply_terraform clean

all: zip_create_short_url zip_redirect_url apply_terraform

zip_create_short_url:
	@echo "Zipping create_short_url..."
	cd $(CREATE_SHORT_URL_DIR) && zip -r ../$(ZIP_CREATE_SHORT_URL) .

zip_redirect_url:
	@echo "Zipping redirect_url..."
	cd $(REDIRECT_URL_DIR) && zip -r ../$(ZIP_REDIRECT_URL) .

zip_all: zip_create_short_url zip_redirect_url

apply_terraform:
	@echo "Applying Terraform configuration..."
	terraform init
	terraform apply -auto-approve

destroy_terraform:
	@echo "Destroying Terraform configuration..."
	terraform destroy -auto-approve

clean:
	@echo "Cleaning up zip files..."
	rm -f $(ZIP_CREATE_SHORT_URL) $(ZIP_REDIRECT_URL)

testApi:
	curl -X POST $(API_GATEWAY_URL)/create \
		-H "Content-Type: application/json" \
		-d '{"url": "https://www.example.com", "suffix": "H3LL0"}'
