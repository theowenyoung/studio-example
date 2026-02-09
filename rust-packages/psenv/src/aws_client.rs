use anyhow::{Context, Result};
use aws_config::meta::region::RegionProviderChain;
use aws_config::profile::ProfileFileCredentialsProvider;
use aws_config::{BehaviorVersion, Region};
use aws_sdk_ssm::Client;
use log::debug;

pub struct AwsClient {
    ssm_client: Client,
}

impl AwsClient {
    pub async fn new(region: Option<&str>, profile: Option<&str>) -> Result<Self> {
        let mut config_loader = aws_config::defaults(BehaviorVersion::latest());

        // Set region if provided
        if let Some(region) = region {
            let region_provider = RegionProviderChain::first_try(Region::new(region.to_string()));
            config_loader = config_loader.region(region_provider);
        }

        // Set profile if provided
        if let Some(profile) = profile {
            let credentials_provider = ProfileFileCredentialsProvider::builder()
                .profile_name(profile)
                .build();
            config_loader = config_loader.credentials_provider(credentials_provider);
        }

        let config = config_loader.load().await;

        debug!("Initialized AWS config with region: {:?}", config.region());

        let ssm_client = Client::new(&config);

        Ok(AwsClient { ssm_client })
    }

    pub async fn get_parameter(&self, name: &str) -> Result<Option<String>> {
        debug!("Getting parameter: {}", name);

        match self
            .ssm_client
            .get_parameter()
            .name(name)
            .with_decryption(true)
            .send()
            .await
        {
            Ok(result) => {
                if let Some(parameter) = result.parameter {
                    if let Some(value) = parameter.value {
                        debug!("Successfully retrieved parameter: {}", name);
                        Ok(Some(value))
                    } else {
                        debug!("Parameter {} has no value", name);
                        Ok(None)
                    }
                } else {
                    debug!("Parameter {} not found", name);
                    Ok(None)
                }
            }
            Err(err) => {
                let service_err = err.into_service_error();
                match service_err {
                    aws_sdk_ssm::operation::get_parameter::GetParameterError::ParameterNotFound(_) => {
                        debug!("Parameter not found: {}", name);
                        Ok(None)
                    }
                    _ => {
                        Err(anyhow::anyhow!("AWS SSM error: {}", service_err))
                            .with_context(|| format!("Failed to get parameter: {}", name))
                    }
                }
            }
        }
    }
}