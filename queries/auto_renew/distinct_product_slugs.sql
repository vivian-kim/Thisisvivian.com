-- reactive to the group dropdown - narrows to that group's slugs
SELECT DISTINCT product_slug
FROM ${subscription_status}
WHERE product_group LIKE '${inputs.group_filter.value}'
ORDER BY product_slug
