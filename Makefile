-include .env

test :; RISC0_DEV_MODE=false forge test
test-dev :; RISC0_DEV_MODE=true forge test
