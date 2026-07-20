-- reactive to the product group dropdown - only shows slugs belonging to
-- the currently selected group (or all slugs if group_filter = 'all')
SELECT DISTINCT product_slug
FROM ${subscription_status}
WHERE product_group LIKE '${inputs.group_filter.value}'
ORDER BY product_slug
