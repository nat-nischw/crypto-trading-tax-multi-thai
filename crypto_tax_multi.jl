#!/usr/bin/env julia
# -*- coding: utf-8 -*-

"""
A command-line tool to calculate crypto gains from multiple CSV files
using FIFO or Moving Average methods.
"""

using ArgParse
using Glob
using CSV
using DataFrames
using ProgressMeter

"""
parse_arguments()
"""
function parse_arguments()
    s = ArgParseSettings()

    @add_arg_table s begin
        "--pattern"
        help = "Glob pattern to find CSV files (default='./tax/2024_name/*/*.csv')."
        default = "./tax/2024_name/*/*.csv"

        "--skiprows"
        help = "Number of rows to skip from top in each CSV file (default=2)."
        arg_type = Int
        default = 2

        "--method"
        help = "Calculation method: 'fifo' (FIFO only), 'ma' (Moving Average only), or 'both'."
        arg_type = String
        default = "both"
    end

    args = parse_args(s)
    valid_methods = ["fifo", "ma", "both"]
    if args["method"] ∉ valid_methods
        error("Invalid value for --method: $(args["method"]). Valid options are: $(join(valid_methods, ", "))")
    end

    return args
end

"""
load_data(file_path, skiprows)

Load CSV data from `file_path`, skip `skiprows` lines from the top,
rename columns, and return a DataFrame.
"""
function load_data(file_path::String, skiprows::Int=2)
    lines = readlines(file_path)
    if skiprows >= length(lines)
        error("skiprows ($skiprows) >= total lines in file ($file_path).")
    end

    lines = lines[(skiprows+1):end]
    csv_str = join(lines, "\n")

    df = CSV.read(IOBuffer(csv_str), DataFrame)

    rename!(df, Dict(
        "Order NUM" => "order_num",
        "Digital Asset Short Name" => "asset",
        "Transaction Date &Time" => "datetime",
        "Transaction Types" => "type",
        "Volume Amount/Execution Volume Amount" => "quantity",
        "Currency Price/Execution price (THB)" => "price",
        "Value (THB)/Execution Value in THB" => "total_value",
        "Fee (THB)" => "fee",
        "NET in THB (Fee Included)" => "net_thb"
    ))

    return df
end

"""
calculate_fifo(df)

Returns a DataFrame of each SELL transaction with realized gain/loss
using FIFO method.
"""
function calculate_fifo(df::DataFrame)
    results = DataFrame(
        order_num = String[],
        datetime = String[],
        asset = String[],
        sell_quantity = Float64[],
        sell_price = Float64[],
        proceeds = Float64[],
        cost_basis = Float64[],
        realized_gain = Float64[]
    )

    # buy_lots: Vector{Tuple{qty_remaining, cost_per_unit}}
    buy_lots = Vector{Tuple{Float64, Float64}}()

    # progress bar
    @showprogress for row in eachrow(df)
        txn_type = lowercase(string(row[:type]))
        qty      = parse(Float64, string(row[:quantity]))
        price    = parse(Float64, string(row[:price]))
        totalval = parse(Float64, string(row[:total_value]))

        if txn_type == "buy"
            cost_per_unit = qty != 0 ? totalval/qty : 0.0
            push!(buy_lots, (qty, cost_per_unit))

        elseif txn_type == "sell"
            sell_qty_remaining = qty
            realized_gain_total = 0.0
            original_cost_total = 0.0

            while sell_qty_remaining > 0 && !isempty(buy_lots)
                (first_lot_qty, first_lot_cost) = buy_lots[1]

                if first_lot_qty <= sell_qty_remaining
                    used_qty = first_lot_qty
                    popfirst!(buy_lots) 
                else
                    used_qty = sell_qty_remaining
                    new_qty = first_lot_qty - used_qty
                    buy_lots[1] = (new_qty, first_lot_cost)
                end

                realized_gain = (price - first_lot_cost) * used_qty
                realized_gain_total += realized_gain
                original_cost_total += first_lot_cost * used_qty

                sell_qty_remaining -= used_qty
            end

            proceeds = price * qty
            push!(results, (
                string(row[:order_num]),
                string(row[:datetime]),
                string(row[:asset]),
                qty,
                price,
                proceeds,
                original_cost_total,
                realized_gain_total
            ))
        end
    end

    return results
end

"""
calculate_moving_average(df)

Returns a DataFrame of each SELL transaction with realized gains
based on moving average cost.
"""
function calculate_moving_average(df::DataFrame)
    results = DataFrame(
        order_num = String[],
        datetime = String[],
        asset = String[],
        sell_quantity = Float64[],
        sell_price = Float64[],
        proceeds = Float64[],
        avg_cost_per_coin = Float64[],
        realized_gain = Float64[]
    )

    coin_balance = 0.0
    avg_cost_per_coin = 0.0

    @showprogress for row in eachrow(df)
        txn_type = lowercase(string(row[:type]))
        qty      = parse(Float64, string(row[:quantity]))
        price    = parse(Float64, string(row[:price]))
        totalval = parse(Float64, string(row[:total_value]))

        if txn_type == "buy"
            old_total_cost = coin_balance * avg_cost_per_coin
            new_total_cost = old_total_cost + totalval
            new_balance = coin_balance + qty

            if new_balance > 0
                new_avg_cost = new_total_cost / new_balance
            else
                new_avg_cost = 0
            end

            coin_balance = new_balance
            avg_cost_per_coin = new_avg_cost

        elseif txn_type == "sell"
            realized_gain = (price - avg_cost_per_coin) * qty
            coin_balance -= qty
            if coin_balance < 0
                coin_balance = 0
            end

            proceeds = price * qty
            push!(results, (
                string(row[:order_num]),
                string(row[:datetime]),
                string(row[:asset]),
                qty,
                price,
                proceeds,
                avg_cost_per_coin,
                realized_gain
            ))
        end
    end

    return results
end

"""
process_file(file_path, skiprows, method)

- Load CSV files
- calculate FIFO, MA or both
- Returns: (df_fifo, df_ma, total_gain_fifo, total_gain_ma)
"""
function process_file(file_path::String, skiprows::Int=2, method::String="both")
    df = load_data(file_path, skiprows)

    df_fifo = DataFrame()
    df_ma   = DataFrame()
    total_gain_fifo = 0.0
    total_gain_ma   = 0.0

    if method in ["fifo", "both"]
        df_fifo = calculate_fifo(df)
        if nrow(df_fifo) > 0
            total_gain_fifo = sum(df_fifo.realized_gain)
        end
    end

    if method in ["ma", "both"]
        df_ma = calculate_moving_average(df)
        if nrow(df_ma) > 0
            # in df_ma, column name realized_gain
            total_gain_ma = sum(df_ma.realized_gain)
        end
    end

    return df_fifo, df_ma, total_gain_fifo, total_gain_ma
end

"""
main()

- parse arguments
- Search files by pattern
- Process all files
- Show totals
"""
function main()
    args = parse_arguments()

    pattern  = args["pattern"]
    skiprows = args["skiprows"]
    method   = args["method"]

    csv_files = glob(pattern)
    if isempty(csv_files)
        println("No CSV files found for pattern: $pattern")
        return
    end

    println("\nFound $(length(csv_files)) file(s) matching: $pattern\n")

    grand_total_fifo = 0.0
    grand_total_ma   = 0.0

    for csv_file in csv_files
        println("Processing file: $csv_file")
        df_fifo, df_ma, total_gain_fifo, total_gain_ma = process_file(csv_file, skiprows, method)

        if method in ["fifo", "both"]
            println("\n=== FIFO Results ===")
            show(df_fifo, allrows=true, allcols=true)  # แสดงตาราง
            println("\nTotal Realized Gain (FIFO): $(round(total_gain_fifo, digits=2)) THB\n")
            grand_total_fifo += total_gain_fifo
        end

        if method in ["ma", "both"]
            println("=== Moving Average Results ===")
            show(df_ma, allrows=true, allcols=true)
            println("\nTotal Realized Gain (Moving Average): $(round(total_gain_ma, digits=2)) THB\n")
            grand_total_ma += total_gain_ma
        end

        # compare if both
        if method == "both"
            if total_gain_fifo > total_gain_ma
                println("[*] FIFO > MA ($(total_gain_fifo) vs. $(total_gain_ma))")
            elseif total_gain_fifo < total_gain_ma
                println("[*] MA > FIFO ($(total_gain_ma) vs. $(total_gain_fifo))")
            else
                println("[*] FIFO == MA")
            end
        end

        println("------------------------------------------------------------")
    end

    # Summarize 
    if method == "fifo"
        println("\nGrand Total (FIFO) from all files: $(round(grand_total_fifo, digits=2)) THB")
    elseif method == "ma"
        println("\nGrand Total (Moving Average) from all files: $(round(grand_total_ma, digits=2)) THB")
    else
        println("\nGrand Total (FIFO): $(round(grand_total_fifo, digits=2)) THB")
        println("Grand Total (Moving Average): $(round(grand_total_ma, digits=2)) THB")
    end
end


if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
