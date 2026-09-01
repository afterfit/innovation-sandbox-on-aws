// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0
import { RemovalPolicy, Stack } from "aws-cdk-lib";
import { Key } from "aws-cdk-lib/aws-kms";
import { Construct } from "constructs";

import { isDevMode } from "@amzn/innovation-sandbox-infrastructure/helpers/deployment-mode";

export class IsbKmsKeys {
  private static instances: { [key: string]: Key } = {};
  public static get(
    scope: Construct,
    namespace: string,
    keyId: string | undefined = undefined,
  ): Key {
    // Use the stack's construct id (not stackName) so the KMS key's logical id
    // and alias stay stable even if the deployed stackName is overridden.
    // Changing this would orphan the existing (RETAIN) key and create a new one.
    const isbKeyId = keyId ?? Stack.of(scope).node.id;
    if (!IsbKmsKeys.instances[isbKeyId]) {
      IsbKmsKeys.instances[isbKeyId] = new Key(
        Stack.of(scope),
        `IsbKmsKey-${isbKeyId}`,
        {
          enableKeyRotation: true,
          description: `Encryption Key for Innovation Sandbox: ${isbKeyId}`,
          alias: `AwsSolutions/InnovationSandbox/${namespace}/${isbKeyId}`,
          removalPolicy: isDevMode(scope)
            ? RemovalPolicy.DESTROY
            : RemovalPolicy.RETAIN,
        },
      );
    }
    return IsbKmsKeys.instances[isbKeyId]!;
  }
}
