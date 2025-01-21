# url-shortner

## How to run the code

To deploy the code and infrastructure on AWS easily using the `Makefile`, start by creating an `.env` file as shown below:

```
AWS_ACCESS_KEY_ID=<your_aws_access_key_id>
AWS_SECRET_ACCESS_KEY=<your_aws_secret_access_key>
```

I am using my own laptop for work, which is why I did not use `aws configure`.

After creating the `.env` file, run `make apply_terraform` to deploy the cloud infrastructure and the Python code in the `./create_short_url` and `./redirect_url` directories. These directories are divided to maintain a single responsibility for each API route. Only the `create_short_url` directory contains a `requirements.txt` file because I used `validator` to verify that the POST request is a valid URL. Other packages are either built-in with Python or come with AWS Lambda instances, such as `boto3`. Uploading ZIP files is preferred over using Docker images since the code is lightweight.

The Terraform output will be in the following format:

```
api_gateway_invoke_url = "https://s5ge7oy690.execute-api.ap-southeast-1.amazonaws.com/prod"
s3_bucket_name = "url-shortener20250109091839172000000001"
simple_html_page_url = "http://url-shortener20250109091839172000000001.s3-website-ap-southeast-1.amazonaws.com"
```

Click the `simple_html_page_url` link to view the work.

## Infrastructure (Terraform)

### S3 Bucket Setup and Static Website Hosting:

For the frontend, an S3 bucket is created to host static website files. Bucket ownership controls and public access block settings are configured for secure access permissions. A bucket policy allows public read access for serving static website content. Static website hosting is enabled on the S3 bucket to serve HTML content with an index document specified.

### Lambda Functions:

Two Lambda functions are defined: one for creating short URLs and another for redirecting to original URLs. Lambda functions are configured with roles and policies to interact with DynamoDB for storing URL mappings and logs. Environment variables are set with the DynamoDB table name.

### DynamoDB Table:

A DynamoDB table stores URL mappings with short URLs as the hash key and an expiry attribute for TTL.

### API Gateway:

An API Gateway REST API handles requests for creating short URLs and redirecting. Methods and integrations are defined for POST and GET methods, including CORS support with OPTIONS methods. A deployment ensures necessary resources are ready, and triggers are set for redeployment if needed. The architecture leverages AWS services for a scalable, serverless URL shortener service. Users can create short URLs stored in DynamoDB and access original URLs through Lambda functions and API Gateway. S3 hosts HTML content.

#### Reminder:

The IP restriction part is commented out for testing purposes. Uncomment to limit API access to specific IP addresses.

```
resource "aws_api_gateway_rest_api_policy" "api_policy" {
  rest_api_id = aws_api_gateway_rest_api.url_shortener.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = [
          aws_lambda_function.create_short_url.arn,
          aws_lambda_function.redirect_url.arn
        ],
        Principal = "*"
      },
      {
        Effect = "Allow"
        Principal = "*"
        Action = "execute-api:Invoke"
        Resource = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.url_shortener.id}/*/*/*"
      },
      # Uncomment the following block to restrict access to the API to a specific IP address
      # {
      #   "Effect": "Deny",
      #   "Principal": "*",
      #   "Action": "execute-api:Invoke",
      #   "Resource": "execute-api:/*/*/*",
      #   "Condition": {
      #     "NotIpAddress": {
      #       "aws:SourceIp": ["218.189.44.128/25"]
      #     }
      #   }
      # }
    ]
  })
}
```

## Lambda Code

### `create_short_url`

This POST request expects JSON like:

This is a POST request which receives a JSON like the following:

```
{"url": "www.example.com", "suffix": "H3LL0"}
```

`url` is the URL to shorten, `suffix` is an optional custom suffix. The `validator` checks if the POST request is a URL. If valid, a record with a randomly generated or custom suffix, the original URL, and expiry time (current time + 10 minutes) is added to the table.

#### Reminder:

The API Gateway URL is used as the domain name for shortened URL since making a domain name costs money and it is only temporary.

### `redirect_url`

This GET request redirects previously generated links. Clicking a shortened URL triggers a GET request, returning the original URL, redirecting users, and extending expiry time by 10 minutes.

## Potential Improvements

- Use Route 53 to register a domain for shortened URLs instead of using the API Gateway URL.
- Integrate a Web Application Firewall (WAF) with API Gateway for added security.
- Implement API Gateway Usage Plans and throttling to control access rates and limit requests per second.
- Enforce HTTPS by configuring Custom Domain Names with TLS certificates for secure transmission.
