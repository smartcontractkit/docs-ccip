# Chainlink CCIP Tutorials

> **NOTE:** This repository represents an educational example to use a Chainlink system, product, or service and is provided to demonstrate how to interact with Chainlink’s systems, products, and services to integrate them into your own. This template is provided “AS IS” and “AS AVAILABLE” without warranties of any kind, it has not been audited, and it may be missing key checks or error handling to make the usage of the system, product or service more clear. Do not use the code in this example in a production environment without completing your own audits and application of best practices. Neither Chainlink Labs, the Chainlink Foundation, nor Chainlink node operators are responsible for unintended outputs that are generated due to errors in code.

Example contracts and scripts for cross-chain development with [Chainlink CCIP](https://docs.chain.link/ccip), using [Foundry](foundry/scripts/tutorials/) and [Hardhat](hardhat/scripts/tutorials/).

## Tutorials

| Tutorial | Description |
|----------|-------------|
| [Token Transfers](foundry/scripts/tutorials/token-transfers/) | Transfer tokens to any address on a destination chain |
| [Send Arbitrary Data](foundry/scripts/tutorials/send-arbitrary-data/) | Send text messages cross-chain |
| [Programmable Token Transfers](foundry/scripts/tutorials/programmable-token-transfers/) | Combine token transfers with arbitrary data |
| [Programmable Defensive Token Transfers](foundry/scripts/tutorials/programmable-defensive-token-transfers/) | Adds error handling and token recovery |
| [Transfer USDC with Data](foundry/scripts/tutorials/transfer-usdc-with-data/) | Transfer USDC cross-chain and trigger on-chain staking |
| [Send Data & Receive Confirmation (A→B→A)](foundry/scripts/tutorials/send-arbitrary-data-and-receive-transfer-confirmation/) | Two-way messaging with source-side status tracking |

Equivalent Hardhat tutorials are available under [hardhat/scripts/tutorials/](hardhat/scripts/tutorials/).

See each tutorial's README for full setup and deployment instructions.

Disclaimer: Please note, this repo contains community examples only  — these are not Chainlink products or services and are not supported or maintained by Chainlink. This code represents an example of using a Chainlink product or service, and is intended for demonstration and educational purposes only. It is provided “AS IS” and “AS AVAILABLE” without warranties of any kind, may not have been audited, and may omit checks or error handling. Each party intending to use this example code does so entirely at their own risk and must perform its own audits, security and code review, key management, and testing before any production deployment and ensure the operation and performance of such code matches expectations. Neither Chainlink Labs nor the Chainlink Foundation deploys, operates, monitors, maintains or endorses any deployment of this code. Note that this is not a Chainlink product, feature or service, and there are no commitments made with respect to the code, including compatibility with future Chainlink releases. You should not rely on this code without first conducting your own technical, engineering, and security review. This code is also outside the scope of any Chainlink bug bounty programs. Neither Chainlink Labs, the Chainlink Foundation, nor Chainlink node operators are responsible for outcomes due to errors in this example or how it is deployed or operated, or liable for any resulting claims or damages. Use of the Chainlink Network is subject to the Chainlink Foundation [Terms of Service](https://chain.link/terms), which provides important information and disclosures. By using this code, you acknowledge and agree to these terms.
