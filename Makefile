-include .env

test :; RISC0_DEV_MODE=false forge test --gas-report
test-dev :; RISC0_DEV_MODE=true forge test --gas-report
