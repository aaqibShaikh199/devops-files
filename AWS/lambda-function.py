#Yeh mera Python ka code hai, jo is tarah se kaam karega ki jab bhi AWS S3 bucket me robots.txt ya sitemap.xml file me koi bhi change hoga, toh yeh code automatically run hoga aur puri CloudFront invalidation process start ho jayegi.

#NOTE: CloudFront distribution ID ko ENV variables me add karna hai 


import boto3
import os

# Initialize the CloudFront client
cloudfront_client = boto3.client('cloudfront')

def lambda_handler(event, context):
    # Get all environment variables starting with 'DISTRIBUTION_ID-'
    distribution_ids = []
    for key in os.environ:
        if key.startswith('DISTRIBUTION_ID_'):
            distribution_ids.append(os.environ[key])  # Fetch the value of each env variable

    # Path to invalidate (invalidate all files)
    paths_to_invalidate = ['/*']

    # Iterate over the distribution IDs and create invalidations for each
    for distribution_id in distribution_ids:
        try:
            response = cloudfront_client.create_invalidation(
                DistributionId=distribution_id.strip(),  # Remove any extra spaces around IDs
                InvalidationBatch={
                    'Paths': {
                        'Quantity': len(paths_to_invalidate),
                        'Items': paths_to_invalidate,
                    },
                    'CallerReference': str(context.aws_request_id)  # Unique reference for each invalidation
                }
            )
            print(f"Invalidation created for Distribution {distribution_id}: {response['Invalidation']['Id']}")
        except Exception as e:
            print(f"Error creating invalidation for Distribution {distribution_id}: {str(e)}")

    return {
        'statusCode': 200,
        'body': "Invalidation requests created for all distributions."
    }
