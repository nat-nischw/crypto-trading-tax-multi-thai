# Crypto-Tax-Multi-Thai
**Crypto-tax-multi-thai** is a set of scripts/programs designed to calculate crypto trading gains and losses from multiple CSV files at once, supporting both the **FIFO (First-In First-Out)** and **Moving Average** methods commonly used for cost basis and crypto tax calculations.

---

## Features

1. **Multi-file support**: Uses a glob pattern (e.g., `./tax/2024_name/*/*.csv`) to find all CSV files in nested directories and process them in one go.  
2. **Two main calculation methods**:  
   - **FIFO**: Match sold coins with the earliest acquired coins first.  
   - **Moving Average**: Update average cost basis after each purchase and use that average cost to calculate gains/losses upon selling.  
3. **Result output**: Displays realized gains for each file and a grand total (sum across all files).  
4. **Configurable**: Use `--skiprows` to skip the top rows (e.g., metadata lines like “Name, ...” or “Tax Year, ...”).  
5. **Easy to customize**: If you need to account for fees, or adapt to different cost basis methods, you can modify the calculation functions accordingly.

---

---
# Installations
## macOS
```bash
brew install zeromq
```
## Linux (Ubuntu / Debian)
```bash
sudo apt-get update
sudo apt-get install libzmq3-dev
```
## Prerequisites
```
julia -e 'using Pkg; Pkg.add(["ArgParse", "CSV", "DataFrames", "Glob", "ProgressMeter"])'
```
---

---
## Usage
1. Adjust the pattern as needed, e.g., ./tax/2024_name/*/*.csv
2. Run the script:
```bash
julia crypto_tax_multi.jl --pattern "./tax/2024_name/*/*.csv" --skiprows 2 --method both
```

- `--pattern`: Specify a glob pattern to find CSV files (default is ./tax/2024_name/*/*.csv).
- `--skiprows`: Skip a specified number of top rows in each CSV (default is 2).
- `--method`: Choose the calculation method:
    - `fifo` = FIFO only
    - `ma` = Moving Average only
    - `both` = run both methods
The script will display each discovered CSV file, calculate gains for each, and then show a grand total for whichever method(s) you select.

---

## Customization

- To include fees in your cost basis or deduct them from proceeds, modify the code in the calculate_fifo and/or calculate_moving_average functions.
- To handle multiple assets in a single file, filter rows by asset or create separate DataFrames per asset.

---

## Disclaimer

- To include fees in your cost basis or deduct them from proceeds, modify the code in the `calculate_fifo` and/or `calculate_moving_average` functions.
- Consult the regulations of your local revenue authority and/or a professional tax/legal advisor for full compliance.
- For more details on crypto tax guidelines in Thailand, please refer to the Revenue Department’s official PDF: [Thai Revenue Department Crypto Tax Manual (PDF)](https://www.rd.go.th/fileadmin/user_upload/lorkhor/information/manual_crypto_310165.pdf)
