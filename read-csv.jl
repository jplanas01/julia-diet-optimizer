import CSV
using JuMP
import GLPK

data = CSV.File("calories.csv")

nutrients = [ "Calories", "Carbs", "Fat", "Protein" ]
nutrient_data = Containers.DenseAxisArray([
	3300 3500;
	0 Inf;
	0 Inf;
	140 180;
	], nutrients, ["min", "max"])
fat_minimum = 0.20
fat_maximum = 0.40

foods = [replace(lowercase(x), " " => "-") for x in data.Food]

costs = Containers.DenseAxisArray([parse(Float64, strip(x, [' ', '$'])) for x in data.Cost] ./ data.Servings, foods)
max_servings = Containers.DenseAxisArray(
	getproperty(data, Symbol("Max servings")), foods)
weights = Containers.DenseAxisArray(
	getproperty(data, Symbol("Serving grams")), foods)

food_data_arr = zeros(Float64, length(foods), length(nutrients))
for (index, nut) in enumerate(nutrients)
	food_data_arr[:,index] = getproperty(data, Symbol(nut))
end
food_data = Containers.DenseAxisArray(food_data_arr, foods, nutrients)

model = Model(GLPK.Optimizer)
@variables(model,
	begin
	0 <= buy[f = foods] <= max_servings[f]
	end)
@objective(model, Min, sum(costs[f] * buy[f] for f in foods))
@constraint(model, [c in nutrients],
	nutrient_data[c, "min"] <= sum(food_data[f, c] * buy[f] for f in foods) <= nutrient_data[c, "max"])
@constraint(model, fat_min,
	fat_minimum * sum(food_data[f, "Calories"] * buy[f] for f in foods) <= sum(food_data[f, "Fat"] * buy[f] for f in foods) * 9)
@constraint(model, fat_max,
	sum(food_data[f, "Fat"] * buy[f] for f in foods) * 9 <= fat_maximum * sum(food_data[f, "Calories"] * buy[f] for f in foods))

for (size, food) in zip(data.Servings, foods)
	if size == 1
		@constraint(model, buy[food] in MOI.Integer())
	end
end

optimize!(model)
println("Foods:")
for food in foods
	if value(buy[food]) > 0.01
		println("$(food) = $(value(buy[food]))")
		if !ismissing(weights[food])
			println("Weight = $(value(buy[food]) * value(weights[food]))")
		end
	end
end
println("")
for nut in nutrients
	total = sum(food_data[f, nut] * value(buy[f]) for f in foods)
	println("$(nut) = $(total)")
end
total_cals = sum(food_data[f, "Calories"] * value(buy[f]) for f in foods)
for (nut, mult) in zip(["Carbs", "Fat", "Protein"], [4, 9, 4])
	total = sum(food_data[f, nut] * value(buy[f]) for f in foods)
	println("$(nut) is $(mult * total / total_cals) of total calories")
end
println("")
println("Total cost: $(sum(value(buy[f]) * costs[f] for f in foods))")
