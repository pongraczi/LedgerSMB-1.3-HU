-- SQL Fixes for upgrades.  These must be safe to run repeatedly, or they must 
-- fail transactionally.  Please:  one transaction per fix.  
--
-- Chris Travers

BEGIN; -- PRE-RC update

ALTER TABLE partscustomer RENAME customer_id TO credit_id;
ALTER TABLE partsvendor RENAME entity_id TO credit_id;

COMMIT;


BEGIN; -- 1.3.4, fix for menu-- David Bandel
update menu_attribute set value = 'receive_order' where value  =
'consolidate_sales_order' and node_id = '65';

update menu_attribute set id = '149' where value  = 'receive_order'
and node_id = '65';

update menu_attribute set value = 'consolidate_sales_order' where
value  = 'receive_order' and node_id = '64';

update menu_attribute set id = '152' where value  =
'consolidate_sales_order' and node_id = '64';

-- fix for bug 3430820
update menu_attribute set value = 'pricegroup' where node_id = '83' and attribute = 'type';
update menu_attribute set value = 'partsgroup' where node_id = '82' and attribute = 'type';

UPDATE menu_attribute SET value = 'partsgroup' WHERE node_id = 91 and attribute = 'type';
UPDATE menu_attribute SET value = 'pricegroup' WHERE node_id = 92 and attribute = 'type';

-- Very restrictive because some people still have Asset handling installed from
-- Addons and so the node_id and id values may not match.  Don't want to break
-- what is working! --CT
UPDATE menu_attribute SET value = 'begin_import' WHERE id = 631 and value = 'import' and node_id = '235'; 

-- Getting rid of System/Backup menu since this is broken

DELETE FROM menu_acl       WHERE node_id BETWEEN 133 AND 135;
DELETE FROM menu_attribute WHERE node_id BETWEEN 133 AND 135;
DELETE FROM menu_node      WHERE id      BETWEEN 133 AND 135;

-- bad batch type for receipt batches
update menu_attribute set value = 'receipt' where node_id = 203 and attribute='batch_type';

COMMIT;

BEGIN;
ALTER TABLE entity_credit_account drop constraint "entity_credit_account_language_code_fkey";
COMMIT;

BEGIN;
ALTER TABLE entity_credit_account ADD FOREIGN KEY (language_code) REFERENCES language(code);
COMMIT;

BEGIN;
UPDATE menu_attribute SET value = 'invoice'
   WHERE node_id = 117 AND attribute = 'type';
UPDATE menu_attribute SET value = 'sales_order'
   WHERE node_id = 118 AND attribute = 'type';
COMMIT;

BEGIN;
ALTER TABLE entity_bank_account DROP CONSTRAINT entity_bank_account_pkey;
ALTER TABLE entity_bank_account ALTER COLUMN bic DROP NOT NULL;
ALTER TABLE entity_bank_account ADD UNIQUE(bic,iban);
CREATE UNIQUE INDEX eba_iban_null_bic_u ON entity_bank_account(iban) WHERE bic IS NULL;
COMMIT;

BEGIN; -- Data fixes for 1.2-1.3 upgrade.  Will fail otherwise --Chris T
UPDATE parts 
   SET income_accno_id = (SELECT account.id 
                            FROM account JOIN lsmb12.chart USING (accno)
                           WHERE chart.id = income_accno_id),
       expense_accno_id = (SELECT account.id 
                            FROM account JOIN lsmb12.chart USING (accno)
                           WHERE chart.id = expense_accno_id),
       inventory_accno_id = (SELECT account.id
                            FROM account JOIN lsmb12.chart USING (accno)
                           WHERE chart.id = inventory_accno_id)
 WHERE id IN (SELECT id FROM lsmb12.parts op 
               WHERE op.id = parts.id 
                     AND (op.income_accno_id = parts.income_accno_id
                          OR op.inventory_accno_id = parts.inventory_accno_id 
                          or op.expense_accno_id = parts.expense_accno_id));
COMMIT; 

BEGIN;
-- Fix menu Shipping -> Ship to actually point to the shipping interface
-- used to point to sales order consolidation
UPDATE menu_attribute
 SET value = 'ship_order'
 WHERE attribute='type'
       AND node_id = (SELECT id FROM menu_node WHERE label = 'Ship');
COMMIT;

BEGIN;
-- fix for non-existant role handling in menu_generate() and related


CREATE OR REPLACE FUNCTION menu_generate() RETURNS SETOF menu_item AS 
$$
DECLARE 
	item menu_item;
	arg menu_attribute%ROWTYPE;
BEGIN
	FOR item IN 
		SELECT n.position, n.id, c.level, n.label, c.path, 
                       to_args(array[ma.attribute, ma.value])
		FROM connectby('menu_node', 'id', 'parent', 'position', '0', 
				0, ',') 
			c(id integer, parent integer, "level" integer, 
				path text, list_order integer)
		JOIN menu_node n USING(id)
                JOIN menu_attribute ma ON (n.id = ma.node_id)
               WHERE n.id IN (select node_id 
                                FROM menu_acl
                                JOIN (select rolname FROM pg_roles
                                      UNION 
                                     select 'public') pgr 
                                     ON pgr.rolname = role_name
                               WHERE pg_has_role(CASE WHEN coalesce(pgr.rolname,
                                                                    'public') 
                                                                    = 'public'
                                                      THEN current_user
                                                      ELSE pgr.rolname
                                                   END, 'USAGE')
                            GROUP BY node_id
                              HAVING bool_and(CASE WHEN acl_type ilike 'DENY'
                                                   THEN FALSE
                                                   WHEN acl_type ilike 'ALLOW'
                                                   THEN TRUE
                                                END))
                    or exists (select cn.id, cc.path
                                 FROM connectby('menu_node', 'id', 'parent', 
                                                'position', '0', 0, ',')
                                      cc(id integer, parent integer, 
                                         "level" integer, path text,
                                         list_order integer)
                                 JOIN menu_node cn USING(id)
                                WHERE cn.id IN 
                                      (select node_id FROM menu_acl
                                        JOIN (select rolname FROM pg_roles
                                              UNION 
                                              select 'public') pgr 
                                              ON pgr.rolname = role_name
                                        WHERE pg_has_role(CASE WHEN coalesce(pgr.rolname,
                                                                    'public') 
                                                                    = 'public'
                                                      THEN current_user
                                                      ELSE pgr.rolname
                                                   END, 'USAGE')
                                     GROUP BY node_id
                                       HAVING bool_and(CASE WHEN acl_type 
                                                                 ilike 'DENY'
                                                            THEN false
                                                            WHEN acl_type 
                                                                 ilike 'ALLOW'
                                                            THEN TRUE
                                                         END))
                                       and cc.path like c.path || ',%')
            GROUP BY n.position, n.id, c.level, n.label, c.path, c.list_order
            ORDER BY c.list_order
                             
	LOOP
		RETURN NEXT item;
	END LOOP;
END;
$$ language plpgsql;

COMMENT ON FUNCTION menu_generate() IS
$$
This function returns the complete menu tree.  It is used to generate nested
menus for the web interface.
$$;

CREATE OR REPLACE FUNCTION menu_children(in_parent_id int) RETURNS SETOF menu_item
AS $$
declare 
	item menu_item;
	arg menu_attribute%ROWTYPE;
begin
        FOR item IN
		SELECT n.position, n.id, c.level, n.label, c.path, 
                       to_args(array[ma.attribute, ma.value])
		FROM connectby('menu_node', 'id', 'parent', 'position', 
				in_parent_id, 1, ',') 
			c(id integer, parent integer, "level" integer, 
				path text, list_order integer)
		JOIN menu_node n USING(id)
                JOIN menu_attribute ma ON (n.id = ma.node_id)
               WHERE n.id IN (select node_id 
                                FROM menu_acl
                                JOIN (select rolname FROM pg_roles
                                      UNION 
                                      select 'public') pgr 
                                      ON pgr.rolname = role_name
                                WHERE pg_has_role(CASE WHEN coalesce(pgr.rolname,
                                                                    'public') 
                                                                    = 'public'
                                                               THEN current_user
                                                               ELSE pgr.rolname
                                                               END, 'USAGE')
                            GROUP BY node_id
                              HAVING bool_and(CASE WHEN acl_type ilike 'DENY'
                                                   THEN FALSE
                                                   WHEN acl_type ilike 'ALLOW'
                                                   THEN TRUE
                                                END))
                    or exists (select cn.id, cc.path
                                 FROM connectby('menu_node', 'id', 'parent', 
                                                'position', '0', 0, ',')
                                      cc(id integer, parent integer, 
                                         "level" integer, path text,
                                         list_order integer)
                                 JOIN menu_node cn USING(id)
                                WHERE cn.id IN 
                                      (select node_id FROM menu_acl
                                         JOIN (select rolname FROM pg_roles
                                              UNION 
                                              select 'public') pgr 
                                              ON pgr.rolname = role_name
                                        WHERE pg_has_role(CASE WHEN coalesce(pgr.rolname,
                                                                    'public') 
                                                                    = 'public'
                                                               THEN current_user
                                                               ELSE pgr.rolname
                                                               END, 'USAGE')
                                     GROUP BY node_id
                                       HAVING bool_and(CASE WHEN acl_type 
                                                                 ilike 'DENY'
                                                            THEN false
                                                            WHEN acl_type 
                                                                 ilike 'ALLOW'
                                                            THEN TRUE
                                                         END))
                                       and cc.path like c.path || ',%')
            GROUP BY n.position, n.id, c.level, n.label, c.path, c.list_order
            ORDER BY c.list_order
        LOOP
                return next item;
        end loop;
end;
$$ language plpgsql;
COMMIT;

BEGIN; -- Search Assets menu
update menu_node set parent = 229 where id = 233;
COMMIT;

BEGIN; -- timecard additional info
ALTER TABLE jcitems ADD total numeric NOT NULL DEFAULT 0;
ALTER TABLE jcitems ADD non_billable numeric NOT NULL DEFAULT 0;

UPDATE jcitems 
   SET total = qty
 WHERE qty IS NOT NULL and total = 0;

COMMIT;

BEGIN;

-- FX RECON 

ALTER TABLE cr_report ADD recon_fx bool default false;

COMMIT;

BEGIN;

-- MIN VALUE FOR TAXES

ALTER TABLE tax ADD minvalue numeric;
ALTER TABLE tax ADD maxvalue numeric;


COMMIT;

BEGIN;

ALTER TABLE mime_type ADD invoice_include bool default false;
UPDATE mime_type SET invoice_include = 'true' where mime_type like 'image/%';

COMMIT;

BEGIN;

UPDATE menu_attribute SET value = 'sales_quotation' 
WHERE node_id = 169 AND attribute = 'template';

UPDATE menu_attribute SET value = 'request_quotation' 
WHERE node_id = 170 AND attribute = 'template';

COMMIT;
BEGIN;

-- fixes for menu taking a long time to render when few permissions are granted

DROP TYPE IF EXISTS menu_item CASCADE;
CREATE TYPE menu_item AS (
   position int,
   id int,
   level int,
   label varchar,
   path varchar,
   parent int,
   args varchar[]
);



CREATE OR REPLACE FUNCTION menu_generate() RETURNS SETOF menu_item AS 
$$
DECLARE 
	item menu_item;
	arg menu_attribute%ROWTYPE;
BEGIN
	FOR item IN 
               WITH RECURSIVE tree (path, id, parent, level, positions)
                               AS (select id::text as path, id, parent, 
                                           0 as level, position::text
                                      FROM menu_node where parent is null
                                     UNION 
                                    select path || ',' || n.id::text, n.id, 
                                           n.parent,
                                           t.level + 1, 
                                           t.positions || ',' || n.position
                                      FROM menu_node n
                                      JOIN tree t ON t.id = n.parent) 
		SELECT n.position, n.id, c.level, n.label, c.path, n.parent,
                       to_args(array[ma.attribute, ma.value])
		FROM tree c
		JOIN menu_node n USING(id)
                JOIN menu_attribute ma ON (n.id = ma.node_id)
               WHERE n.id IN (select node_id 
                                FROM menu_acl acl
                          LEFT JOIN pg_roles pr on pr.rolname = acl.role_name
                               WHERE CASE WHEN role_name 
                                                           ilike 'public'
                                                      THEN true
                                                      WHEN rolname IS NULL
                                                      THEN FALSE
                                                      ELSE pg_has_role(rolname,
                                                                       'USAGE')
                                      END
                            GROUP BY node_id
                              HAVING bool_and(CASE WHEN acl_type ilike 'DENY'
                                                   THEN FALSE
                                                   WHEN acl_type ilike 'ALLOW'
                                                   THEN TRUE
                                                END))
                    or exists (select cn.id, cc.path
                                 FROM tree cc
                                 JOIN menu_node cn USING(id)
                                WHERE cn.id IN 
                                      (select node_id 
                                         FROM menu_acl acl
                                    LEFT JOIN pg_roles pr 
                                              on pr.rolname = acl.role_name
                                        WHERE CASE WHEN rolname 
                                                           ilike 'public'
                                                      THEN true
                                                      WHEN rolname IS NULL
                                                      THEN FALSE
                                                      ELSE pg_has_role(rolname,
                                                                       'USAGE')
                                                END
                                     GROUP BY node_id
                                       HAVING bool_and(CASE WHEN acl_type 
                                                                 ilike 'DENY'
                                                            THEN false
                                                            WHEN acl_type 
                                                                 ilike 'ALLOW'
                                                            THEN TRUE
                                                         END))
                                       and cc.path::text 
                                           like c.path::text || ',%')
            GROUP BY n.position, n.id, c.level, n.label, c.path, c.positions,
                     n.parent
            ORDER BY string_to_array(c.positions, ',')::int[]
	LOOP
		RETURN NEXT item;
	END LOOP;
END;
$$ language plpgsql;

COMMENT ON FUNCTION menu_generate() IS
$$
This function returns the complete menu tree.  It is used to generate nested
menus for the web interface.
$$;

CREATE OR REPLACE FUNCTION menu_children(in_parent_id int) RETURNS SETOF menu_item
AS $$
SELECT * FROM menu_generate() where parent = $1;
$$ language sql;

COMMENT ON FUNCTION menu_children(int) IS 
$$ This function returns all menu  items which are children of in_parent_id 
(the only input parameter). 

It is thus similar to menu_generate() but it only returns the menu items 
associated with nodes directly descendant from the parent.  It is used for
menues for frameless browsers.$$;

CREATE OR REPLACE FUNCTION 
menu_insert(in_parent_id int, in_position int, in_label text)
returns int
AS $$
DECLARE
	new_id int;
BEGIN
	UPDATE menu_node 
	SET position = position * -1
	WHERE parent = in_parent_id
		AND position >= in_position;

	INSERT INTO menu_node (parent, position, label)
	VALUES (in_parent_id, in_position, in_label);

	SELECT INTO new_id currval('menu_node_id_seq');

	UPDATE menu_node 
	SET position = (position * -1) + 1
	WHERE parent = in_parent_id
		AND position < 0;

	RETURN new_id;
END;
$$ language plpgsql;

comment on function menu_insert(int, int, text) is $$
This function inserts menu items at arbitrary positions.  The arguments are, in
order:  parent, position, label.  The return value is the id number of the menu
item created. $$;

DROP VIEW menu_friendly;
CREATE VIEW menu_friendly AS
WITH RECURSIVE tree (path, id, parent, level, positions)
                               AS (select id::text as path, id, parent, 
                                           0 as level, position::text
                                      FROM menu_node where parent is null
                                     UNION 
                                    select path || ',' || n.id::text, n.id, 
                                           n.parent,
                                           t.level + 1, 
                                           t.positions || ',' || n.position
                                      FROM menu_node n
                                      JOIN tree t ON t.id = n.parent) 
SELECT t."level", t.path,
       (repeat(' '::text, (2 * t."level")) || (n.label)::text) AS label, 
        n.id, n."position" 
   FROM tree t
   JOIN menu_node n USING (id)
  ORDER BY string_to_array(t.positions, ',')::int[];

COMMENT ON VIEW menu_friendly IS
$$ A nice human-readable view for investigating the menu tree.  Does not
show menu attributes or acls.$$;

COMMIT;

BEGIN;
-- Fix for menu anomilies
DELETE FROM menu_acl
 where node_id in (select node_id from menu_attribute where attribute = 'menu');

COMMIT;

BEGIN;
-- fix primary key for make/model
ALTER TABLE makemodel DROP CONSTRAINT makemodel_pkey;
ALTER TABLE makemodel ADD PRIMARY KEY(parts_id, make, model);
COMMIT;

BEGIN;
-- performance fix for all years list  functions

create index ac_transdate_year_idx on acc_trans(EXTRACT ('YEAR' FROM transdate));

COMMIT;

BEGIN;
-- RECEIPT REVERSAL broken:

insert into batch_class (id,class) values (7,'receipt_reversal');

COMMIT;

BEGIN;

-- FIXING AP MENU

 update menu_attribute set value = 'tax_paid' where node_id = 28 and attribute = 'report';

update menu_attribute set value = 'ap_aging' where node_id = 27 and attribute = 'report';

COMMIT;

BEGIN;

-- inventory from 1.3.30 and lower

UPDATE parts 
   SET onhand = onhand + coalesce((select sum(qty) 
                            from inventory 
                           where orderitems_id 
                                 IN (select id 
                                       from orderitems oi
                                       join oe on oi.trans_id = oe.id
                                      where closed is not true)
                                 and parts_id = parts.id), 0)
 WHERE string_to_array((setting_get('version')).value::text, '.')::int[] 
       < '{1,3,31}';

COMMIT;

BEGIN;
delete from menu_attribute where node_id = 192 and attribute = 'menu';

DELETE FROM menu_acl WHERE node_id = 60 AND exists (select 1 from menu_attribute where node_id = 60 and attribute = 'menu');

COMMIT;

BEGIN;
ALTER FUNCTION admin__save_user(int, int, text, text, bool) SET datestyle = 'ISO,YMD';
ALTER FUNCTION user__change_password(text) SET datestyle = 'ISO,YMD';
COMMIT;

BEGIN;
ALTER TABLE ar DISABLE TRIGGER ALL;
ALTER TABLE ap DISABLE TRIGGER ALL;

ALTER TABLE ap ADD COLUMN crdate date;
ALTER TABLE ar ADD COLUMN crdate date;

UPDATE ap SET crdate=transdate;
UPDATE ar SET crdate=transdate;

COMMENT ON COLUMN ap.crdate IS
$$ This is for recording the AR/AP creation date, which is always that date, when the invoice created. This is different, than transdate or duedate.
This kind of date does not effect on ledger/financial data, but for administrative purposes in Hungary, probably in other countries, too.
Use case:
if somebody pay in cash, crdate=transdate=duedate
if somebody will receive goods T+5 days and have 15 days term, the dates are the following:  crdate: now,  transdate=crdate+5,  duedate=transdate+15.
There are rules in Hungary, how to fill out a correct invoice, where the crdate and transdate should be important.$$;

COMMENT ON COLUMN ar.crdate IS
$$ This is for recording the AR/AP creation date, which is always that date, when the invoice created. This is different, than transdate or duedate.
This kind of date does not effect on ledger/financial data, but for administrative purposes in Hungary, probably in other countries, too.
Use case:
if somebody pay in cash, crdate=transdate=duedate
if somebody will receive goods T+5 days and have 15 days term, the dates are the following:  crdate: now,  transdate=crdate+5,  duedate=transdate+15.
There are rules in Hungary, how to fill out a correct invoice, where the crdate and transdate should be important.$$;

ALTER TABLE ar ENABLE TRIGGER ALL;
ALTER TABLE ap ENABLE TRIGGER ALL;

COMMIT;

BEGIN;
	ALTER TABLE entity_bank_account ADD COLUMN remark varchar;
	COMMENT ON COLUMN entity_bank_account.remark IS
$$ This field contains the notes for an account, like: This is USD account, this one is HUF account, this one is the default account, this account for paying specific taxes. If a partner has more than one account, now you are able to write remarks for them.
$$;

DROP FUNCTION eca__save_bank_account (int, int, text, text, int);
DROP FUNCTION entity__save_bank_account (int, text, text, int);

CREATE OR REPLACE FUNCTION eca__save_bank_account
(in_entity_id int, in_credit_id int, in_bic text, in_iban text, in_remark text,
in_bank_account_id int)
RETURNS int AS
$$
DECLARE out_id int;
BEGIN
        UPDATE entity_bank_account
           SET bic = in_bic,
               iban = in_iban,
               remark = in_remark
         WHERE id = in_bank_account_id;

        IF FOUND THEN   
                out_id = in_bank_account_id;
        ELSE
                INSERT INTO entity_bank_account(entity_id, bic, iban, remark)
                VALUES(in_entity_id, in_bic, in_iban, in_remark);
                SELECT CURRVAL('entity_bank_account_id_seq') INTO out_id ;
        END IF;

        IF in_credit_id IS NOT NULL THEN
                UPDATE entity_credit_account SET bank_account = out_id
                WHERE id = in_credit_id;
        END IF;

        RETURN out_id;
END;
$$ LANGUAGE PLPGSQL;

COMMENT ON  FUNCTION eca__save_bank_account
(in_entity_id int, in_credit_id int, in_bic text, in_iban text, in_remark text,
in_bank_account_id int) IS
$$ Saves bank account to the credit account.$$;

CREATE OR REPLACE FUNCTION entity__save_bank_account
(in_entity_id int, in_bic text, in_iban text, in_remark text, in_bank_account_id int)
RETURNS int AS
$$
DECLARE out_id int;     
BEGIN   
        UPDATE entity_bank_account
           SET bic = in_bic,
               iban = in_iban,
               remark = in_remark
         WHERE id = in_bank_account_id;

        IF FOUND THEN
                out_id = in_bank_account_id;
        ELSE   
                INSERT INTO entity_bank_account(entity_id, bic, iban, remark)
                VALUES(in_entity_id, in_bic, in_iban, in_remark);
                SELECT CURRVAL('entity_bank_account_id_seq') INTO out_id ;
        END IF;

        RETURN out_id;
END;
$$ LANGUAGE PLPGSQL;

COMMENT ON FUNCTION entity__save_bank_account
(in_entity_id int, in_bic text, in_iban text, in_remark text, in_bank_account_id int) IS
$$Saves a bank account to the entity.$$;

COMMIT;

BEGIN;
ALTER TABLE location ALTER COLUMN mail_code DROP NOT NULL;
COMMIT;

BEGIN;
UPDATE menu_attribute 
   SET value = 'sales_quotation' 
 where value = 'quotation' AND attribute='template';
COMMIT;

BEGIN;
CREATE FUNCTION prevent_closed_transactions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE t_end_date date;
BEGIN
SELECT max(end_date) into t_end_date FROM account_checkpoint;
IF new.transdate <= t_end_date THEN
    RAISE EXCEPTION 'Transaction entered into closed period.  Transdate: %',
                   new.transdate;
END IF;
RETURN new;
END;
$$;


CREATE TRIGGER acc_trans_prevent_closed BEFORE INSERT ON acc_trans 
FOR EACH ROW EXECUTE PROCEDURE prevent_closed_transactions();
CREATE TRIGGER ap_prevent_closed BEFORE INSERT ON ap 
FOR EACH ROW EXECUTE PROCEDURE prevent_closed_transactions();
CREATE TRIGGER ar_prevent_closed BEFORE INSERT ON ar 
FOR EACH ROW EXECUTE PROCEDURE prevent_closed_transactions();
CREATE TRIGGER gl_prevent_closed BEFORE INSERT ON gl 
FOR EACH ROW EXECUTE PROCEDURE prevent_closed_transactions();
COMMIT;

BEGIN;
INSERT INTO defaults VALUES ('disable_back', '0');
COMMIT;

BEGIN;
ALTER TABLE batch DROP CONSTRAINT "batch_locked_by_fkey";
ALTER TABLE batch ADD FOREIGN KEY (locked_by) REFERENCES session(session_id)
ON DELETE SET NULL;
COMMIT;

BEGIN;

ALTER TABLE invoice ALTER COLUMN allocated TYPE NUMERIC;

COMMIT;

BEGIN;
ALTER TABLE entity_employee ADD is_manager bool DEFAULT FALSE;
UPDATE entity_employee SET is_manager = true WHERE role = 'manager';

COMMIT;

BEGIN;
ALTER TABLE BATCH DROP CONSTRAINT "batch_locked_by_fkey";

ALTER TABLE BATCH ADD FOREIGN KEY (locked_by) references session (session_id)
ON DELETE SET NULL;

COMMIT;

BEGIN;
ALTER TABLE invoice ADD vendor_sku text;
UPDATE invoice SET vendor_sku = (select min(partnumber) from partsvendor
                                  where parts_id = invoice.parts_id
                                        AND credit_id = (
                                                 select entity_credit_account
                                                   from ap
                                                  where ap.id = invoice.trans_id
                                        )
                                )
 WHERE trans_id in (select id from ap);
COMMIT;

BEGIN;

CREATE TABLE lsmb_sequence (
   label text primary key,
   setting_key text not null references defaults(setting_key),
   prefix text,
   suffix text,
   sequence text not null default '1',
   accept_input bool default true
);

COMMIT;
