-include .env

build:; forge build

test:; forge test

test-fork:; forge test --fork-url https://arb1.arbitrum.io/rpc

coverage:; forge coverage --fork-url https://arb1.arbitrum.io/rpc

clean:; forge clean

deploy:; forge script script/DeployPresale.s.sol:DeployPresale --rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY) --broadcast
