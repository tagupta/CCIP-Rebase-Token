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
