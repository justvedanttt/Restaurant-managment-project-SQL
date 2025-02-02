create table customers(CustomerID serial primary key,
Name varchar,
ContactNumber varchar,
Email varchar,
LoyaltyPoints int
);


create table staffs(StaffID serial primary key,
Name	varchar,
Role	varchar,
ContactNumber varchar
);


create table menu_category(CategoryID serial primary key,
CategoryName varchar
);


create table menu(MenuID serial primary key,
CategoryID int references menu_category(CategoryID),
ItemName varchar,
Price numeric,
Description varchar
);


create table Dining_Tables(Table_id serial primary key,
Status varchar
);


create table Inventory(InventoryID serial primary key,
ItemName	varchar,
Quantity	int,
Threshold int
);


create table Orders(OrderID serial primary key,
StaffID int references staffs(StaffID),
Table_id int references Dining_tables(Table_id),
CustomerID int references Customers(CustomerID),
OrderDate timestamp
);


create table Order_items(OrderItemID	serial primary key,
OrderID	int references Orders(OrderID),
MenuID	int references Menu(MenuID),
Quantity INT
);


create table Payments(PaymentID serial primary key,
OrderID	int references Orders(OrderID),
Amount real,
PaymentDate	timestamp,
PaymentMethod varchar
);

--- STORED PROCEDURE---

--Register a new customer. 
CREATE OR REPLACE PROCEDURE RegisterNewCustomer( 
p_FirstName VARCHAR, 
p_LastName VARCHAR, 
p_Email VARCHAR, 
p_Phone VARCHAR, 
p_Address TEXT 
) 
LANGUAGE plpgsql AS $$ 
DECLARE 
v_CustomerID INT;
v_Fullname text;
BEGIN
v_Fullname := p_Firstname || '' || p_Lastname;
INSERT INTO Customers (Fullname, Email, Phone, Address, 
RegistrationDate) 
VALUES (v_Fullname, p_Email, p_Phone, p_Address, CURRENT_DATE) 
RETURNING CustomerID INTO v_CustomerID;
RAISE NOTICE 'New customer % registered successfully with CustomerID: %', 
 v_Fullname,v_CustomerID; 
END; 
$$; 

--Process an order and update table availability. 
CREATE OR REPLACE PROCEDURE ProcessOrderSimple( 
p_CustomerID INT, 
p_StaffID INT, 
p_TableID INT, 
p_TotalAmount DECIMAL 
) 
LANGUAGE plpgsql AS $$ 
DECLARE 
v_OrderID INT; 
BEGIN -- Update table availability 
UPDATE Tables SET IsAvailable = FALSE WHERE TableID = p_TableID; -- Create a new order 
INSERT INTO Orders (CustomerID, StaffID, TableID, OrderDate, TotalAmount) 
VALUES (p_CustomerID, p_StaffID, p_TableID, CURRENT_TIMESTAMP, p_TotalAmount) 
RETURNING OrderID INTO v_OrderID; -- Output confirmation 
RAISE NOTICE 'Order % created successfully for Customer %.', v_OrderID, 
p_CustomerID; 
END; 
$$;


--Update inventory based on ordered items  
CREATE OR REPLACE PROCEDURE UpdateInventoryForOrder( 
    p_OrderID INT 
) 
LANGUAGE plpgsql AS $$ 
DECLARE 
    v_MenuID INT; 
    v_Quantity INT; 
    v_IngredientID INT; 
    v_RequiredQuantity INT;	item RECORD;
	ingredient RECORD;
BEGIN 
FOR item IN  
SELECT MenuID, Quantity FROM Order_Items WHERE OrderID = p_OrderID 
LOOP 
FOR ingredient IN  
SELECT IngredientID, QuantityRequired 
FROM Recipe 
WHERE MenuID = item.MenuID 
LOOP 
v_RequiredQuantity := ingredient.QuantityRequired * item.Quantity;
UPDATE Inventory
SET Quantity = Quantity - v_RequiredQuantity 
WHERE IngredientID = ingredient.IngredientID; 
IF (SELECT Quantity FROM Inventory WHERE IngredientID = 
ingredient.IngredientID) < 10 THEN 
RAISE NOTICE 'Low stock for IngredientID %: Less than 10 remaining.', 
ingredient.IngredientID; 
END IF; 
END LOOP; 
END LOOP; 
RAISE NOTICE 'Inventory updated successfully for OrderID: %', p_OrderID; 
END;
$$;


Calculate daily revenue and generate a sales report.  
CREATE OR REPLACE PROCEDURE GenerateDailySalesReport( p_ReportDate DATE 
) 
LANGUAGE plpgsql AS $$ 
DECLARE 
v_TotalRevenue DECIMAL;
sale RECORD;
BEGIN 
SELECT SUM(TotalAmount) 
INTO v_TotalRevenue 
FROM Orders 
WHERE DATE(OrderDate) = p_ReportDate; 
RAISE NOTICE 'Total Revenue for %: %', p_ReportDate, COALESCE(v_TotalRevenue, 0); 
RAISE NOTICE 'Sales Report for %:', p_ReportDate; 
FOR sale IN 
SELECT OrderID, CustomerID, TableID, TotalAmount, OrderDate 
FROM Orders 
WHERE DATE(OrderDate) = p_ReportDate 
LOOP 
RAISE NOTICE 'OrderID: %, CustomerID: %, TableID: %, Amount: %, Date: %', 
sale.OrderID, sale.CustomerID, sale.TableID, sale.TotalAmount, sale.OrderDate; 
END LOOP; 
END; 
$$;

---FUNCTIONS---

--Fetch Customer Loyalty Points 
CREATE OR REPLACE FUNCTION FetchCustomerLoyaltyPoints(p_CustomerID INT) 
RETURNS INT AS $$ 
DECLARE 
    v_LoyaltyPoints INT; 
BEGIN 
    SELECT COALESCE(LoyaltyPoints, 0)  
    INTO v_LoyaltyPoints 
    FROM Customer   
	WHERE CustomerID = p_CustomerID; 
    RETURN v_LoyaltyPoints; 
END; 
$$ LANGUAGE plpgsql;


--Calculate Total Cost of an Order with Applicable Discounts 
CREATE OR REPLACE FUNCTION CalculateOrderTotalWithLoyalty(p_OrderID INT) 
RETURNS DECIMAL AS $$ 
DECLARE 
v_TotalCost DECIMAL := 0; 
v_LoyaltyPoints INT := 0; 
v_DiscountAmount DECIMAL := 0; 
v_CustomerID INT; 
BEGIN 
SELECT CustomerID 
INTO v_CustomerID 
FROM Orders 
WHERE OrderID = p_OrderID;
SELECT COALESCE(LoyaltyPoints, 0) 
INTO v_LoyaltyPoints 
FROM Customer 
WHERE CustomerID = v_CustomerID;
SELECT SUM(oi.Quantity * m.Price) 
INTO v_TotalCost 
FROM Order_Items oi 
JOIN Menu m ON oi.MenuID = m.MenuID 
WHERE oi.OrderID = p_OrderID;  
v_DiscountAmount := v_LoyaltyPoints * 0.5; 
IF v_DiscountAmount > v_TotalCost THEN 
v_DiscountAmount := v_TotalCost; 
END IF;
v_TotalCost := v_TotalCost - v_DiscountAmount; 
RETURN v_TotalCost; 
END; 
$$ LANGUAGE plpgsql; 


--Identify Low-Stock Inventory Items 
CREATE OR REPLACE FUNCTION IdentifyLowStockItems(p_Threshold INT) 
RETURNS TABLE (IngredientID INT, IngredientName VARCHAR, CurrentQuantity INT) AS 
$$ 
BEGIN 
RETURN QUERY 
SELECT IngredientID, IngredientName, Quantity 
FROM Inventory
WHERE Quantity < p_Threshold; 
END; 
$$ LANGUAGE plpgsql;


---TRIGGERS---

--1. Automatically Updating Table Availability After Order Processing 
CREATE OR REPLACE FUNCTION UpdateTableAvailability() 
RETURNS TRIGGER AS $$ 
BEGIN  
UPDATE Tables 
SET IsAvailable = FALSE 
WHERE TableID = NEW.TableID; 
RETURN NEW; 
END; 
$$ LANGUAGE plpgsql;

CREATE TRIGGER AfterOrderPlaced 
AFTER INSERT ON orders
FOR EACH ROW 
EXECUTE FUNCTION UpdateTableAvailability();


--2. Deducting Inventory Quantities After an Order Is Placed 
CREATE OR REPLACE FUNCTION DeductInventory() 
RETURNS TRIGGER AS $$ 
BEGIN
UPDATE Inventory 
SET Quantity = Quantity - NEW.Quantity 
WHERE IngredientID = NEW.IngredientID; 
RETURN NEW; 
END; 
$$ LANGUAGE plpgsql;

CREATE TRIGGER AfterOrderItemAdded 
AFTER INSERT ON Order_Items 
FOR EACH ROW 
EXECUTE FUNCTION DeductInventory();


--3. Logging Price Changes in the Menu 
CREATE TABLE PriceChangeLog ( 
LogID SERIAL PRIMARY KEY, 
MenuID INT  REFERENCES Menu(MenuID), 
OldPrice DECIMAL NOT NULL, 
NewPrice DECIMAL NOT NULL, 
ChangeDate TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE OR REPLACE FUNCTION LogPriceChange() 
RETURNS TRIGGER AS $$ 
BEGIN
INSERT INTO PriceChangeLog (MenuID, OldPrice, NewPrice) 
VALUES (OLD.MenuID, OLD.Price, NEW.Price); 
RETURN NEW; 
END; 
$$ LANGUAGE plpgsql;

CREATE TRIGGER AfterPriceUpdate 
AFTER UPDATE OF Price ON menu
FOR EACH ROW 
WHEN (OLD.Price IS DISTINCT FROM NEW.Price) 
EXECUTE FUNCTION LogPriceChange();


--- ADVANCED QUERY WRITING---

--Identify Top-Selling Items by Category 
SELECT  
c.CategoryName, 
m.itemName, 
SUM(oi.Quantity) AS TotalQuantitySold 
FROM  
Menu_Category c 
JOIN  
Menu m ON c.CategoryID = m.CategoryID 
JOIN  
Order_Items oi ON m.MenuID = oi.MenuID 
GROUP BY  
c.CategoryName, m.itemName 
ORDER BY  
c.CategoryName, TotalQuantitySold DESC;


--Find Peak Dining Hours 
SELECT  
EXTRACT(HOUR FROM o.OrderDate) AS Hour, 
COUNT(o.OrderID) AS TotalOrders 
FROM  
Orders o 
GROUP BY  
EXTRACT(HOUR FROM o.OrderDate) 
ORDER BY  
TotalOrders DESC;


--Rank Staff Based on Orders Processed 
SELECT  
s.StaffID, 
s.Name, 
COUNT(o.OrderID) AS TotalOrdersProcessed, 
RANK() OVER (ORDER BY COUNT(o.OrderID) DESC) AS Rank 
FROM  
Staffs s 
LEFT JOIN  
Orders o ON s.StaffID = o.StaffID 
GROUP BY  
s.StaffID, s.Name 
ORDER BY
TotalOrdersProcessed DESC;


--Analyze Monthly Revenue Trends 
SELECT  
TO_CHAR(o.OrderDate, 'YYYY-MM') AS Month, 
SUM(p.Amount) AS TotalRevenue 
FROM  
Orders o 
JOIN  
Payments p ON o.OrderID = p.OrderID 
GROUP BY  
TO_CHAR(o.OrderDate, 'YYYY-MM') 
ORDER BY  
Month; 


--- DATA ANALYTICS AND REPORTING---

--Monthly Revenue Trends 
SELECT  
TO_CHAR(o.OrderDate, 'YYYY-MM') AS Month, 
SUM(p.Amount) AS TotalRevenue 
FROM  
Orders o 
JOIN  
Payments p ON o.OrderID = p.OrderID 
GROUP BY  
TO_CHAR(o.OrderDate, 'YYYY-MM') 
ORDER BY  
Month; 


--Category-Wise Sales Performance 
SELECT  
c.CategoryName, 
SUM(oi.Quantity) AS TotalQuantitySold, 
SUM(oi.Quantity * m.Price) AS TotalRevenue 
FROM  
Menu_Category c 
JOIN  
Menu m ON c.CategoryID = m.CategoryID 
JOIN  
Order_Items oi ON m.MenuID = oi.MenuID 
GROUP BY  
c.CategoryName 
ORDER BY  
TotalRevenue DESC;


--Inventory Status Reports 
SELECT  
i.InventoryID, 
i.ItemName, 
i.Quantity, 
CASE  
WHEN i.Quantity < 10 THEN 'Low Stock' 
ELSE 'Sufficient Stock' 
END AS StockStatus 
FROM  
Inventory i 
ORDER BY  
Quantity ASC;


---SECURITY AND ACCESS CONTROL---

-- Create roles 
CREATE ROLE Admin; 
CREATE ROLE Manager; 
CREATE ROLE Staff;

--Grant Privileges --Admin: Full Access 
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO Admin; 
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO Admin;

--Manager: Reporting and Staff Management 
GRANT SELECT ON Orders, Payments, Menu, Menu_Category TO Manager; 
GRANT SELECT, INSERT, UPDATE ON Staffs TO Manager;

--Staff: Order Processing Only 
GRANT SELECT, INSERT, UPDATE ON Orders, Order_Items TO Staff; 
GRANT SELECT ON Menu, dining_tables TO Staff;

--Create Users and Assign Roles
-- Create users 
CREATE USER admin_user WITH PASSWORD 'Admin@123'; 
CREATE USER manager_user WITH PASSWORD 'Manager@123'; 
CREATE USER staff_user WITH PASSWORD 'Staff@123'; 

-- Assign roles to users 
GRANT Admin TO admin_user; 
GRANT Manager TO manager_user; 
GRANT Staff TO staff_user;

--Revoking Permissions 
-- Revoke public access to ensure security 
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC; 
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;


---AUTOMATION ENHANCMENT---

--Real-Time Inventory Tracking and Alerts 
CREATE OR REPLACE FUNCTION update_inventory_on_order() 
RETURNS TRIGGER AS $$ 
BEGIN 
UPDATE Inventory 
SET StockQuantity = StockQuantity - NEW.Quantity 
WHERE InventoryID = NEW.InventoryID; 
RETURN NEW; 
END; 
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_inventory 
AFTER INSERT ON Order_Items 
FOR EACH ROW 
EXECUTE FUNCTION update_inventory_on_order();

--Stored Procedure: Low-Stock Alerts 
CREATE OR REPLACE FUNCTION check_low_stock() 
RETURNS VOID AS $$ 
BEGIN 
INSERT INTO Inventory_Alerts (InventoryID, AlertMessage, AlertDate) 
SELECT InventoryID, 'Low stock alert: Quantity below threshold', CURRENT_DATE 
FROM Inventory 
WHERE StockQuantity < 10; 
END; 
$$ LANGUAGE plpgsql;


--Automatic Generation of Reports and Insights 
CREATE OR REPLACE FUNCTION generate_monthly_revenue_report() 
RETURNS VOID AS $$ 
BEGIN 
INSERT INTO Revenue_Report (Month, TotalRevenue) 
SELECT  
TO_CHAR(OrderDate, 'YYYY-MM') AS Month, 
SUM(PaymentAmount) AS TotalRevenue 
FROM Orders 
JOIN Payments ON Orders.OrderID = Payments.OrderID 
GROUP BY TO_CHAR(OrderDate, 'YYYY-MM'); 
END; 
$$ LANGUAGE plpgsql; 


--Integration of Online Reservations with Table Availability Updates 
CREATE TABLE Online_Reservations ( 
ReservationID SERIAL PRIMARY KEY, 
Table_ID INT REFERENCES dining_tables(Table_ID), 
CustomerID INT REFERENCES Customers(CustomerID), 
ReservationTime TIMESTAMP, 
Status VARCHAR(20) DEFAULT 'Booked' 
); 

CREATE OR REPLACE FUNCTION update_table_availability() 
RETURNS TRIGGER AS $$ 
BEGIN 
UPDATE Tables 
SET IsAvailable = FALSE 
WHERE TableID = NEW.TableID; 
RETURN NEW; 
END; 
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_table_availability 
AFTER INSERT ON Online_Reservations 
FOR EACH ROW 
EXECUTE FUNCTION update_table_availability();