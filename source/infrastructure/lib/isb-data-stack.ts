// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
import { CfnMapping, CfnOutput, Stack, StackProps } from "aws-cdk-lib";
import { Construct } from "constructs";

import { addParameterGroup } from "@amzn/innovation-sandbox-infrastructure/helpers/cfn-utils";
import { NamespaceParam } from "@amzn/innovation-sandbox-infrastructure/helpers/shared-cfn-params";
import { applyIsbTag } from "@amzn/innovation-sandbox-infrastructure/helpers/tagging-helper";
import { IsbDataResources } from "@amzn/innovation-sandbox-infrastructure/isb-data-resources";

export class IsbDataStack extends Stack {
  public static cfnMapping: CfnMapping;
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    const namespaceParam = new NamespaceParam(this);

    addParameterGroup(this, {
      label: "Data Stack Configuration",
      parameters: [namespaceParam],
    });

    const dataResources = new IsbDataResources(this, {
      namespace: namespaceParam.valueAsString,
    });

    applyIsbTag(this, `${namespaceParam.valueAsString}`);

    new CfnOutput(this, "ConfigApplicationIdOut", {
      exportName: `${this.node.id}-ConfigApplicationId`,
      key: `ConfigApplicationId`,
      value: dataResources.config.application.applicationId,
    });

    new CfnOutput(this, "ConfigEnvironmentIdOut", {
      exportName: `${this.node.id}-ConfigEnvironmentId`,
      key: `ConfigEnvironmentId`,
      value: dataResources.config.environment.environmentId,
    });

    new CfnOutput(this, "ConfigDeploymentStrategyIdOut", {
      exportName: `${this.node.id}-ConfigDeploymentStrategyId`,
      key: `ConfigDeploymentStrategyId`,
      value: dataResources.config.deploymentStrategy.deploymentStrategyId,
    });

    new CfnOutput(this, "GlobalConfigConfigurationProfileIdOut", {
      exportName: `${this.node.id}-GlobalConfigConfigurationProfileId`,
      key: `GlobalConfigConfigurationProfileId`,
      value:
        dataResources.config.globalConfigHostedConfiguration
          .configurationProfileId,
    });

    new CfnOutput(this, "NukeConfigConfigurationProfileIdOut", {
      exportName: `${this.node.id}-NukeConfigConfigurationProfileId`,
      key: `NukeConfigConfigurationProfileId`,
      value:
        dataResources.config.nukeConfigHostedConfiguration
          .configurationProfileId,
    });

    new CfnOutput(this, "ReportingConfigConfigurationProfileIdOut", {
      exportName: `${this.node.id}-ReportingConfigConfigurationId`,
      key: `ReportingConfigConfigurationId`,
      value:
        dataResources.config.reportingConfigHostedConfiguration
          .configurationProfileId,
    });

    new CfnOutput(this, "SandboxAccountTableOut", {
      exportName: `${this.node.id}-SandboxAccountTable`,
      key: `SandboxAccountTable`,
      value: dataResources.sandboxAccountTable.tableName,
    });

    new CfnOutput(this, "LeaseTemplateTableOut", {
      exportName: `${this.node.id}-LeaseTemplateTable`,
      key: `LeaseTemplateTable`,
      value: dataResources.leaseTemplateTable.tableName,
    });

    new CfnOutput(this, "LeaseTableOut", {
      exportName: `${this.node.id}-LeaseTable`,
      key: `LeaseTable`,
      value: dataResources.leaseTable.tableName,
    });
  }
}
