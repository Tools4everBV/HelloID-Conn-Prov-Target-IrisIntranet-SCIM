# HelloID-Conn-Prov-Target-IrisIntranet

> [!IMPORTANT]
> This connector has been upgraded to a HelloID PowerShell v2 connector and refactored to meet the latest standards.
Please note that it was updated without a working test environment, so we recommend validating it during implementation.

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://www.tools4ever.nl/connector-logos/irisintranet-logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-IrisIntranet](#helloid-conn-prov-target-irisintranet)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [email](#email)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-IrisIntranet_ is a _target_ connector. _IrisIntranet_ provides a set of REST APIs that allow you to programmatically interact with its data.

## Supported features

The following features are available:

| Feature                                   | Supported | Actions                         | Remarks          |
| ----------------------------------------- | --------- | ------------------------------- | ---------------- |
| **Account Lifecycle**                     | ✅         | Create, Update, Enable, Disable | No delete action |
| **Permissions**                           | ❌         | -                               |                  |
| **Resources**                             | ❌         | -                               |                  |
| **Entitlement Import: Accounts**          | ✅         | -                               |                  |
| **Entitlement Import: Permissions**       | ❌         | -                               |                  |
| **Governance Reconciliation Resolutions** | ✅         | -                               |                  |

## Getting started

### HelloID Icon URL
URL of the icon used for the HelloID Provisioning target system.
```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Target-IrisIntranet/refs/heads/main/Icon.png
```

### Connection settings

The following settings are required to connect to the API.

| Setting  | Description                                                                                                  |
| -------- | ------------------------------------------------------------------------------------------------------------ |
| ApiID    | The API-ID is the unique name for the API to identify it's purpose                                           |
| ApiToken | The API Token used to authenticate against Iris Intranet. This must be retrieved from within the application |
| Uri      | The URL to connect to Iris Intranet. [https://mycompany.irisintranet.com]                                    |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _IrisIntranet_ to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `PersonContext.Person.ExternalId` |
| Account correlation field | `ExternalId`                      |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Account Reference

The account reference is populated with the property `id` property from _IrisIntranet_

## Remarks

### email
- **Only use primary email**: The connector only uses the primary email address of an account. As a result, no email addresses other than the primary address are available in the `personData` within HelloID.
In `update.ps1`, the script only compares the primary email address from IrisIntranet with the value from the field mapping to determine whether an update is required.


## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint | HTTP Method      | Description                                  |
| -------- | ---------------- | -------------------------------------------- |
| /Users   | GET, POST, PATCH | Retrieve, Create and update user information |

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
