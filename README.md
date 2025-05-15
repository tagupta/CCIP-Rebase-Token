# Cross chain rebase token

1. A protocol that allow users to depoit tokens into a Vault andin return receive rebase tokens that represent their underlying balance and accrued interest.

   - 10 ETH and accrued 1 reward => Total of 11 rebase tokens. Can redeem these 11 rebase tokens for 11 ETH

2. Rebase token -> balanceOf function is dynamic to show the changing balance with time

   - Balance increases linearly with time
   - mint tokens to our users every time they perform an action (minting, transferring, burning or bridging)

3. Interest rate
   - Individually set an interest rate for each user based on the global interest rate of the protocol at the time user deposits into the vault.
   - This global interest rate can only decrease to incentivise/reward early adopters.
   - Increase user adoption

# Contract Layout

- version
- imports
- interfaces, libraries and contracts
- errors
- type declarations
- state variables
- events
- modifiers
- functions

# Layout of functions

- constructor
- receive function (if exists)
- fallback function (if exists)
- external
- public
- internal
- private
- view and pure functions

# Caveats

- The admin may grant itself the role to mint and burn rebase tokens, this is a bit centralized part of the contract.
- Let's say a user has two wallets and he has deposited liquidity using both of the wallets. Wallet A has an interest rate of X and wallet B has an interest rate of X - Y. If user tries to move all the funds from A to B, then the final interest rate would become X - Y.
- Let's say a user has a wallet A with an interest rate of X. The global interest rate got changed to something less than X, say X - Y. In this scenario, if user tries to move all funds from wallet A to a brand new wallet B, then the new interest rate of wallet B would become X.
