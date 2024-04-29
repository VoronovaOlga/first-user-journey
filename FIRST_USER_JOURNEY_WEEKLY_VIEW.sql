create or replace view WORKSPACE_OVORONOVA.PUBLIC.FIRST_USER_JOURNEY_WEEKLY(
	SIGN_UP_WEEK,
	USERS_SIGN_UP,
	AVG_DAYS_TO_FST_APPT,
	AVG_DAYS_TO_FST_ORDER,
	PCH_USERS_W_APPT,
	PCH_USERS_W_ORDERS,
	AVG_FST_ORDER_VALUE
) as(
  SELECT sign_up_week,
             COUNT(user_id) AS users_sign_up,
             AVG(appt_tat) AS avg_days_to_fst_appt,
             AVG(order_tat) AS avg_days_to_fst_order,
             COUNT(appt_tat) / COUNT(*) AS pch_users_w_appt,
             COUNT (order_tat) / COUNT(*) AS pch_users_w_orders,
             AVG(fst_order_value) AS avg_fst_order_value
      FROM WORKSPACE_OVORONOVA.PUBLIC.FIRST_USER_JOURNEY
      GROUP BY 1 
      ORDER BY 1
);
