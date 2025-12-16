forge install
forge remappings > remappings.txt

forge build
forge fmt
forge test -vvv

forge clean && forge build

Local smoke-test (Anvil)
Start local chain
anvil

Deploy example contract (Counter)
export RPC_URL=http://127.0.0.1:8545
export PRIVATE_KEY=0x<ANVIL_PRIVATE_KEY>

forge create src/Counter.sol:Counter \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast

  Set deployed address:

export COUNTER_ADDR=0x<DEPLOYED_TO>


Read / write via cast:

cast call $COUNTER_ADDR "number()(uint256)" --rpc-url $RPC_URL

cast send $COUNTER_ADDR "increment()" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

cast call $COUNTER_ADDR "number()(uint256)" --rpc-url $RPC_URL

5) Sepolia deploy + verify
Create .env (DO NOT COMMIT)
SEPOLIA_URL="https://<YOUR_SEPOLIA_RPC>"
PRIVATE_KEY="0x<YOUR_TESTNET_PRIVATE_KEY>"
ETHERSCAN_API_KEY="<YOUR_ETHERSCAN_API_KEY>"


Load env:

source .env

Deploy (forge create)
forge create src/Counter.sol:Counter \
  --rpc-url $SEPOLIA_URL \
  --private-key $PRIVATE_KEY \
  --broadcast


Set address:

export COUNTER_ADDR=0x<DEPLOYED_TO>


Check it works:

cast call $COUNTER_ADDR "number()(uint256)" --rpc-url $SEPOLIA_URL
cast send $COUNTER_ADDR "increment()" --rpc-url $SEPOLIA_URL --private-key $PRIVATE_KEY
cast call $COUNTER_ADDR "number()(uint256)" --rpc-url $SEPOLIA_URL

Verify on Etherscan (to get Read/Write Contract in browser)
Option A: deploy + verify (preferred for new deploys)
forge create src/Counter.sol:Counter \
  --rpc-url $SEPOLIA_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --verifier etherscan \
  --etherscan-api-key $ETHERSCAN_API_KEY

Option B: verify already deployed contract
forge verify-contract --watch --chain sepolia \
  $COUNTER_ADDR \
  src/Counter.sol:Counter \
  --verifier etherscan \
  --etherscan-api-key $ETHERSCAN_API_KEY


After verification:

open the contract address on Sepolia Etherscan

Contract → Read Contract / Write Contract

Write Contract → Connect to Web3 (MetaMask in Sepolia)

