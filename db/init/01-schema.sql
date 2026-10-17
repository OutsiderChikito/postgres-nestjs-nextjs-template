BEGIN;

-- =============================================================
-- APP JHONY - MODELO DE DATOS V2
-- PostgreSQL
-- Alcance: gestion de pedidos de restaurante.
-- No incluye pagos.
-- =============================================================

-- -------------------------------------------------------------
-- 1. USUARIOS
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS app_user (
    user_id        VARCHAR(80)  PRIMARY KEY,
    full_name      VARCHAR(120) NOT NULL,
    role           VARCHAR(20)  NOT NULL,
    password_hash  VARCHAR(255) NOT NULL,
    active         BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by     VARCHAR(80),
    changed_at     TIMESTAMPTZ,
    changed_by     VARCHAR(80),

    CONSTRAINT ck_app_user_role
        CHECK (role IN ('ADMINISTRADOR', 'JEFE', 'MESERO')),

    CONSTRAINT fk_app_user_created_by
        FOREIGN KEY (created_by) REFERENCES app_user(user_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT fk_app_user_changed_by
        FOREIGN KEY (changed_by) REFERENCES app_user(user_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
);

COMMENT ON COLUMN app_user.password_hash IS
'Hash de la contrasena. Nunca almacenar contrasenas en texto plano.';

COMMENT ON COLUMN app_user.created_by IS
'Puede ser NULL para el primer usuario tecnico/administrador del sistema.';

-- -------------------------------------------------------------
-- 2. MESAS
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS restaurant_table (
    table_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name         VARCHAR(20) NOT NULL UNIQUE,
    active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by   VARCHAR(80),
    changed_at   TIMESTAMPTZ,
    changed_by   VARCHAR(80),

    CONSTRAINT fk_restaurant_table_created_by
        FOREIGN KEY (created_by) REFERENCES app_user(user_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT fk_restaurant_table_changed_by
        FOREIGN KEY (changed_by) REFERENCES app_user(user_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
);

-- -------------------------------------------------------------
-- 3. CATEGORIAS
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS category (
    category_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name         VARCHAR(80)  NOT NULL UNIQUE,
    description  VARCHAR(150),
    active       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by   VARCHAR(80),
    changed_at   TIMESTAMPTZ,
    changed_by   VARCHAR(80),

    CONSTRAINT fk_category_created_by
        FOREIGN KEY (created_by) REFERENCES app_user(user_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT fk_category_changed_by
        FOREIGN KEY (changed_by) REFERENCES app_user(user_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
);

-- -------------------------------------------------------------
-- 4. PRODUCTOS
-- El maestro contiene el estado ACTUAL del producto.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS product (
    product_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name              VARCHAR(100) NOT NULL,
    description       VARCHAR(150),
    category_id       BIGINT       NOT NULL,
    requires_cooking  BOOLEAN      NOT NULL DEFAULT FALSE,
    current_price     NUMERIC(12,2) NOT NULL,
    current_cost      NUMERIC(12,2) NOT NULL,
    active            BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMPTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by        VARCHAR(80),
    changed_at        TIMESTAMPTZ,
    changed_by        VARCHAR(80),

    CONSTRAINT ck_product_current_price
        CHECK (current_price >= 0),

    CONSTRAINT ck_product_current_cost
        CHECK (current_cost >= 0),

    CONSTRAINT fk_product_category
        FOREIGN KEY (category_id) REFERENCES category(category_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT fk_product_created_by
        FOREIGN KEY (created_by) REFERENCES app_user(user_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT fk_product_changed_by
        FOREIGN KEY (changed_by) REFERENCES app_user(user_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
);

-- -------------------------------------------------------------
-- 5. PEDIDOS
-- Estados fijos, sin tabla catalogo:
-- BORRADOR -> ABIERTO -> CERRADO
-- BORRADOR/ABIERTO -> CANCELADO
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS restaurant_order (
    order_id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_id             BIGINT      NOT NULL,
    assigned_waiter_id   VARCHAR(80) NOT NULL,
    version              INTEGER     NOT NULL DEFAULT 1,
    status               VARCHAR(20) NOT NULL DEFAULT 'BORRADOR',
    cancellation_reason  VARCHAR(250),
    total_price          NUMERIC(12,2) NOT NULL DEFAULT 0,
    business_date        DATE        NOT NULL DEFAULT CURRENT_DATE,
    opened_at            TIMESTAMPTZ,
    closed_at            TIMESTAMPTZ,
    cancelled_at         TIMESTAMPTZ,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by           VARCHAR(80) NOT NULL,
    changed_at           TIMESTAMPTZ,
    changed_by           VARCHAR(80),

    CONSTRAINT ck_restaurant_order_status
        CHECK (status IN ('BORRADOR', 'ABIERTO', 'CERRADO', 'CANCELADO')),

    CONSTRAINT ck_restaurant_order_version
        CHECK (version > 0),

    CONSTRAINT ck_restaurant_order_total_price
        CHECK (total_price >= 0),

    CONSTRAINT ck_restaurant_order_cancellation_reason
        CHECK (
            (status = 'CANCELADO' AND NULLIF(BTRIM(cancellation_reason), '') IS NOT NULL)
            OR
            (status <> 'CANCELADO' AND cancellation_reason IS NULL)
        ),

    CONSTRAINT ck_restaurant_order_closed_at
        CHECK (status <> 'CERRADO' OR closed_at IS NOT NULL),

    CONSTRAINT ck_restaurant_order_cancelled_at
        CHECK (status <> 'CANCELADO' OR cancelled_at IS NOT NULL),

    CONSTRAINT fk_restaurant_order_table
        FOREIGN KEY (table_id) REFERENCES restaurant_table(table_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT fk_restaurant_order_waiter
        FOREIGN KEY (assigned_waiter_id) REFERENCES app_user(user_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT fk_restaurant_order_created_by
        FOREIGN KEY (created_by) REFERENCES app_user(user_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT fk_restaurant_order_changed_by
        FOREIGN KEY (changed_by) REFERENCES app_user(user_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
);

COMMENT ON COLUMN restaurant_order.business_date IS
'Fecha operativa del pedido para reportes diarios. Permite separar la fecha de negocio del timestamp exacto.';

COMMENT ON COLUMN restaurant_order.version IS
'Version utilizada para optimistic locking desde el backend.';

-- Una mesa no puede tener mas de un pedido activo a la vez.
CREATE UNIQUE INDEX IF NOT EXISTS uq_restaurant_order_active_table
    ON restaurant_order(table_id)
    WHERE status IN ('BORRADOR', 'ABIERTO');

-- -------------------------------------------------------------
-- 6. POSICIONES DEL PEDIDO
-- Guarda una fotografia historica del producto al momento del pedido.
-- No se debe cambiar product_id para reemplazar un producto.
-- Para un reemplazo se crea una nueva posicion y se marca la anterior
-- como REEMPLAZADO.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS order_item (
    item_id                    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id                   BIGINT        NOT NULL,
    product_id                 BIGINT        NOT NULL,

    product_name_snapshot      VARCHAR(100)  NOT NULL,
    category_id_snapshot       BIGINT        NOT NULL,
    category_name_snapshot     VARCHAR(80)   NOT NULL,
    requires_cooking_snapshot  BOOLEAN       NOT NULL,

    quantity                   INTEGER       NOT NULL,
    unit_price                 NUMERIC(12,2) NOT NULL,
    unit_cost                  NUMERIC(12,2) NOT NULL,

    observation                VARCHAR(250),

    status                     VARCHAR(20) NOT NULL DEFAULT 'ACTIVO',

    replaces_item_id           BIGINT UNIQUE,

    created_at                 TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by                 VARCHAR(80) NOT NULL,

    changed_at                 TIMESTAMPTZ,
    changed_by                 VARCHAR(80),

    CONSTRAINT ck_order_item_quantity
        CHECK (quantity > 0),

    CONSTRAINT ck_order_item_unit_price
        CHECK (unit_price >= 0),

    CONSTRAINT ck_order_item_unit_cost
        CHECK (unit_cost >= 0),

    CONSTRAINT ck_order_item_status
        CHECK (
            status IN (
                'ACTIVO',
                'CANCELADO',
                'REEMPLAZADO'
            )
        ),

    CONSTRAINT ck_order_item_not_self_replacement
        CHECK (
            replaces_item_id IS NULL
            OR replaces_item_id <> item_id
        ),

    CONSTRAINT fk_order_item_order
        FOREIGN KEY (order_id)
        REFERENCES restaurant_order(order_id)
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,

    CONSTRAINT fk_order_item_product
        FOREIGN KEY (product_id)
        REFERENCES product(product_id)
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,

    CONSTRAINT fk_order_item_category_snapshot
        FOREIGN KEY (category_id_snapshot)
        REFERENCES category(category_id)
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,

    CONSTRAINT fk_order_item_replaces
        FOREIGN KEY (replaces_item_id)
        REFERENCES order_item(item_id)
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,

    CONSTRAINT fk_order_item_created_by
        FOREIGN KEY (created_by)
        REFERENCES app_user(user_id)
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,

    CONSTRAINT fk_order_item_changed_by
        FOREIGN KEY (changed_by)
        REFERENCES app_user(user_id)
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
);

-- -------------------------------------------------------------
-- 7. AUDITORIA DE CAMBIOS DE POSICIONES
-- Los datos historicos se conservan en JSONB para auditoria.
-- Los reportes operativos deben usar order_item, no esta tabla.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS order_item_event (
    event_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id     BIGINT       NOT NULL,
    item_id      BIGINT       NOT NULL,
    event_type   VARCHAR(20)  NOT NULL,
    old_data     JSONB,
    new_data     JSONB,
    reason       VARCHAR(250),
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by   VARCHAR(80)  NOT NULL,

    CONSTRAINT ck_order_item_event_type
        CHECK (event_type IN ('CREADO', 'MODIFICADO', 'CANCELADO', 'REEMPLAZADO')),

    CONSTRAINT fk_order_item_event_order
        FOREIGN KEY (order_id) REFERENCES restaurant_order(order_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT fk_order_item_event_item
        FOREIGN KEY (item_id) REFERENCES order_item(item_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT fk_order_item_event_created_by
        FOREIGN KEY (created_by) REFERENCES app_user(user_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
);

-- -------------------------------------------------------------
-- 8. TICKETS DE COCINA
-- Un ticket representa un lote de platos enviados a cocina.
-- Solo incluye order_item que requerian cocina al momento del pedido.
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS kitchen_ticket (
    ticket_id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id               BIGINT      NOT NULL,
    status                 VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
    printed_at             TIMESTAMPTZ,
    printed_by             VARCHAR(80),
    print_attempts         INTEGER     NOT NULL DEFAULT 0,
    last_print_attempt_at  TIMESTAMPTZ,
    last_error             VARCHAR(500),
    created_at             TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by             VARCHAR(80) NOT NULL,

    CONSTRAINT ck_kitchen_ticket_status
        CHECK (status IN ('PENDIENTE', 'IMPRESO', 'ERROR')),

    CONSTRAINT ck_kitchen_ticket_print_attempts
        CHECK (print_attempts >= 0),

    CONSTRAINT ck_kitchen_ticket_printed_data
        CHECK (
            status <> 'IMPRESO'
            OR (printed_at IS NOT NULL AND printed_by IS NOT NULL)
        ),

    CONSTRAINT fk_kitchen_ticket_order
        FOREIGN KEY (order_id) REFERENCES restaurant_order(order_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT fk_kitchen_ticket_printed_by
        FOREIGN KEY (printed_by) REFERENCES app_user(user_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT fk_kitchen_ticket_created_by
        FOREIGN KEY (created_by) REFERENCES app_user(user_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
);

CREATE TABLE IF NOT EXISTS kitchen_ticket_item (
    ticket_id      BIGINT NOT NULL,
    order_item_id  BIGINT NOT NULL,

    PRIMARY KEY (ticket_id, order_item_id),

    -- Una posicion se envia a cocina una sola vez.
    -- Una reimpresion debe reutilizar el mismo ticket.
    CONSTRAINT uq_kitchen_ticket_item_order_item UNIQUE (order_item_id),

    CONSTRAINT fk_kitchen_ticket_item_ticket
        FOREIGN KEY (ticket_id) REFERENCES kitchen_ticket(ticket_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT fk_kitchen_ticket_item_order_item
        FOREIGN KEY (order_item_id) REFERENCES order_item(item_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
);

-- Cada intento de impresion queda historizado. Esto permite distinguir
-- la primera impresion de una reimpresion o de un intento fallido.
CREATE TABLE IF NOT EXISTS kitchen_ticket_print (
    print_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ticket_id       BIGINT      NOT NULL,
    result          VARCHAR(20) NOT NULL,
    error_message   VARCHAR(500),
    attempted_at    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    attempted_by    VARCHAR(80) NOT NULL,

    CONSTRAINT ck_kitchen_ticket_print_result
        CHECK (result IN ('IMPRESO', 'ERROR')),

    CONSTRAINT ck_kitchen_ticket_print_error
        CHECK (
            (result = 'ERROR' AND NULLIF(BTRIM(error_message), '') IS NOT NULL)
            OR
            (result = 'IMPRESO' AND error_message IS NULL)
        ),

    CONSTRAINT fk_kitchen_ticket_print_ticket
        FOREIGN KEY (ticket_id) REFERENCES kitchen_ticket(ticket_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION,

    CONSTRAINT fk_kitchen_ticket_print_attempted_by
        FOREIGN KEY (attempted_by) REFERENCES app_user(user_id)
        ON UPDATE NO ACTION ON DELETE NO ACTION
);

-- =============================================================
-- FUNCIONES Y TRIGGERS
-- =============================================================

-- -------------------------------------------------------------
-- 9. Actualizacion automatica de changed_at en tablas maestras
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_set_changed_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.changed_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_app_user_set_changed_at ON app_user;
CREATE TRIGGER trg_app_user_set_changed_at
BEFORE UPDATE ON app_user
FOR EACH ROW
EXECUTE FUNCTION fn_set_changed_at();

DROP TRIGGER IF EXISTS trg_restaurant_table_set_changed_at ON restaurant_table;
CREATE TRIGGER trg_restaurant_table_set_changed_at
BEFORE UPDATE ON restaurant_table
FOR EACH ROW
EXECUTE FUNCTION fn_set_changed_at();

DROP TRIGGER IF EXISTS trg_category_set_changed_at ON category;
CREATE TRIGGER trg_category_set_changed_at
BEFORE UPDATE ON category
FOR EACH ROW
EXECUTE FUNCTION fn_set_changed_at();

DROP TRIGGER IF EXISTS trg_product_set_changed_at ON product;
CREATE TRIGGER trg_product_set_changed_at
BEFORE UPDATE ON product
FOR EACH ROW
EXECUTE FUNCTION fn_set_changed_at();

-- -------------------------------------------------------------
-- 10. Control de estados y version del pedido
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_restaurant_order_before_write()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status = 'ABIERTO' AND NEW.opened_at IS NULL THEN
            NEW.opened_at := CURRENT_TIMESTAMP;
        ELSIF NEW.status = 'CERRADO' THEN
            RAISE EXCEPTION 'Un pedido nuevo no puede crearse directamente en estado CERRADO';
        END IF;

        IF NEW.status = 'CANCELADO' AND NEW.cancelled_at IS NULL THEN
            NEW.cancelled_at := CURRENT_TIMESTAMP;
        END IF;

        RETURN NEW;
    END IF;

    -- Estados terminales: no se reabren ni se siguen modificando.
    IF OLD.status IN ('CERRADO', 'CANCELADO') THEN
        RAISE EXCEPTION 'El pedido % esta en estado % y no puede modificarse', OLD.order_id, OLD.status;
    END IF;

    -- Transiciones permitidas.
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        IF OLD.status = 'BORRADOR' AND NEW.status NOT IN ('ABIERTO', 'CANCELADO') THEN
            RAISE EXCEPTION 'Transicion de estado no permitida: % -> %', OLD.status, NEW.status;
        END IF;

        IF OLD.status = 'ABIERTO' AND NEW.status NOT IN ('CERRADO', 'CANCELADO') THEN
            RAISE EXCEPTION 'Transicion de estado no permitida: % -> %', OLD.status, NEW.status;
        END IF;

        IF NEW.status = 'ABIERTO' AND NEW.opened_at IS NULL THEN
            NEW.opened_at := CURRENT_TIMESTAMP;
        END IF;

        IF NEW.status = 'CERRADO' THEN
            -- No se cierra un pedido mientras exista algun plato activo
            -- que aun no haya sido impreso para cocina.
            IF EXISTS (
                SELECT 1
                  FROM order_item oi
                 WHERE oi.order_id = OLD.order_id
                   AND oi.status = 'ACTIVO'
                   AND oi.requires_cooking_snapshot = TRUE
                   AND NOT EXISTS (
                       SELECT 1
                         FROM kitchen_ticket_item kti
                         JOIN kitchen_ticket kt ON kt.ticket_id = kti.ticket_id
                        WHERE kti.order_item_id = oi.item_id
                          AND kt.status = 'IMPRESO'
                   )
            ) THEN
                RAISE EXCEPTION 'No se puede cerrar el pedido %. Existen platos activos aun no impresos para cocina',
                    OLD.order_id;
            END IF;

            IF NEW.closed_at IS NULL THEN
                NEW.closed_at := CURRENT_TIMESTAMP;
            END IF;
        END IF;

        IF NEW.status = 'CANCELADO' THEN
            -- Si cocina ya recibio un ticket, el pedido completo no puede
            -- anularse porque implicaria anular platos ya enviados.
            IF EXISTS (
                SELECT 1
                  FROM kitchen_ticket
                 WHERE order_id = OLD.order_id
                   AND status = 'IMPRESO'
            ) THEN
                RAISE EXCEPTION 'No se puede cancelar el pedido %. Ya existen tickets impresos para cocina',
                    OLD.order_id;
            END IF;

            IF NEW.cancelled_at IS NULL THEN
                NEW.cancelled_at := CURRENT_TIMESTAMP;
            END IF;
        END IF;
    END IF;

    -- Optimistic locking: el backend debe hacer el UPDATE con
    -- WHERE order_id = ? AND version = <version_leida>.
    NEW.version := OLD.version + 1;
    NEW.changed_at := CURRENT_TIMESTAMP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_restaurant_order_before_write ON restaurant_order;
CREATE TRIGGER trg_restaurant_order_before_write
BEFORE INSERT OR UPDATE ON restaurant_order
FOR EACH ROW
EXECUTE FUNCTION fn_restaurant_order_before_write();

-- -------------------------------------------------------------
-- 11. Snapshot automatico de producto y validaciones de order_item
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_order_item_before_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_status   VARCHAR(20);
    v_product_active  BOOLEAN;
    v_category_active BOOLEAN;
    v_product_name   VARCHAR(100);
    v_category_id    BIGINT;
    v_category_name  VARCHAR(80);
    v_requires       BOOLEAN;
    v_price          NUMERIC(12,2);
    v_cost           NUMERIC(12,2);
    v_old_order_id   BIGINT;
    v_old_status     VARCHAR(20);
BEGIN
    SELECT status
      INTO v_order_status
      FROM restaurant_order
     WHERE order_id = NEW.order_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pedido % no existe', NEW.order_id;
    END IF;

    IF v_order_status NOT IN ('BORRADOR', 'ABIERTO') THEN
        RAISE EXCEPTION 'No se pueden agregar posiciones a un pedido en estado %', v_order_status;
    END IF;

    SELECT p.active,
           c.active,
           p.name,
           p.category_id,
           c.name,
           p.requires_cooking,
           p.current_price,
           p.current_cost
      INTO v_product_active,
           v_category_active,
           v_product_name,
           v_category_id,
           v_category_name,
           v_requires,
           v_price,
           v_cost
      FROM product p
      JOIN category c ON c.category_id = p.category_id
     WHERE p.product_id = NEW.product_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Producto % no existe', NEW.product_id;
    END IF;

    IF NOT v_product_active THEN
        RAISE EXCEPTION 'Producto % esta inactivo y no puede agregarse al pedido', NEW.product_id;
    END IF;

    IF NOT v_category_active THEN
        RAISE EXCEPTION 'La categoria del producto % esta inactiva', NEW.product_id;
    END IF;

    -- La base de datos toma la fotografia historica del maestro.
    NEW.product_name_snapshot := v_product_name;
    NEW.category_id_snapshot := v_category_id;
    NEW.category_name_snapshot := v_category_name;
    NEW.requires_cooking_snapshot := v_requires;
    NEW.unit_price := v_price;
    NEW.unit_cost := v_cost;

    IF NEW.replaces_item_id IS NOT NULL THEN
        SELECT order_id, status
          INTO v_old_order_id, v_old_status
          FROM order_item
         WHERE item_id = NEW.replaces_item_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'La posicion reemplazada % no existe', NEW.replaces_item_id;
        END IF;

        IF v_old_order_id <> NEW.order_id THEN
            RAISE EXCEPTION 'La posicion reemplazada debe pertenecer al mismo pedido';
        END IF;

        IF v_old_status NOT IN ('ACTIVO', 'REEMPLAZADO') THEN
            RAISE EXCEPTION 'La posicion % no puede ser reemplazada porque esta en estado %',
                NEW.replaces_item_id, v_old_status;
        END IF;

        IF EXISTS (
            SELECT 1
              FROM kitchen_ticket_item kti
              JOIN kitchen_ticket kt ON kt.ticket_id = kti.ticket_id
             WHERE kti.order_item_id = NEW.replaces_item_id
               AND kt.status = 'IMPRESO'
        ) THEN
            RAISE EXCEPTION 'La posicion % ya fue impresa para cocina y no puede reemplazarse',
                NEW.replaces_item_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_order_item_before_insert ON order_item;
CREATE TRIGGER trg_order_item_before_insert
BEFORE INSERT ON order_item
FOR EACH ROW
EXECUTE FUNCTION fn_order_item_before_insert();

CREATE OR REPLACE FUNCTION fn_order_item_before_update()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_status VARCHAR(20);
BEGIN
    SELECT status
      INTO v_order_status
      FROM restaurant_order
     WHERE order_id = OLD.order_id;

    IF v_order_status NOT IN ('BORRADOR', 'ABIERTO') THEN
        RAISE EXCEPTION 'No se puede modificar una posicion de un pedido en estado %', v_order_status;
    END IF;

    -- Si ya fue impreso para cocina, la posicion queda bloqueada.
    IF EXISTS (
        SELECT 1
          FROM kitchen_ticket_item kti
          JOIN kitchen_ticket kt ON kt.ticket_id = kti.ticket_id
         WHERE kti.order_item_id = OLD.item_id
           AND kt.status = 'IMPRESO'
    ) THEN
        RAISE EXCEPTION 'La posicion % ya fue impresa para cocina y no puede modificarse ni cancelarse',
            OLD.item_id;
    END IF;

    -- Para cambiar el producto se debe crear una nueva posicion.
    IF NEW.product_id IS DISTINCT FROM OLD.product_id THEN
        RAISE EXCEPTION 'No se permite cambiar product_id. Cree una nueva posicion y marque la anterior como REEMPLAZADO';
    END IF;

    -- Los snapshots economicos y descriptivos son historicos e inmutables.
    IF NEW.product_name_snapshot IS DISTINCT FROM OLD.product_name_snapshot
       OR NEW.category_id_snapshot IS DISTINCT FROM OLD.category_id_snapshot
       OR NEW.category_name_snapshot IS DISTINCT FROM OLD.category_name_snapshot
       OR NEW.requires_cooking_snapshot IS DISTINCT FROM OLD.requires_cooking_snapshot
       OR NEW.unit_price IS DISTINCT FROM OLD.unit_price
       OR NEW.unit_cost IS DISTINCT FROM OLD.unit_cost
       OR NEW.order_id IS DISTINCT FROM OLD.order_id
       OR NEW.created_at IS DISTINCT FROM OLD.created_at
       OR NEW.created_by IS DISTINCT FROM OLD.created_by THEN
        RAISE EXCEPTION 'No se permite modificar datos historicos/inmutables de order_item %', OLD.item_id;
    END IF;

    -- Una posicion cancelada o reemplazada no vuelve a ACTIVO.
    IF OLD.status IN ('CANCELADO', 'REEMPLAZADO') AND NEW.status IS DISTINCT FROM OLD.status THEN
        RAISE EXCEPTION 'La posicion % esta en estado % y no puede cambiar de estado', OLD.item_id, OLD.status;
    END IF;

    IF OLD.status = 'ACTIVO'
       AND NEW.status IS DISTINCT FROM OLD.status
       AND NEW.status NOT IN ('CANCELADO', 'REEMPLAZADO') THEN
        RAISE EXCEPTION 'Transicion de estado de posicion no permitida: % -> %', OLD.status, NEW.status;
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status AND NEW.changed_by IS NULL THEN
        RAISE EXCEPTION 'changed_by es obligatorio al cancelar o reemplazar una posicion';
    END IF;

    NEW.changed_at := CURRENT_TIMESTAMP;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_order_item_before_update ON order_item;
CREATE TRIGGER trg_order_item_before_update
BEFORE UPDATE ON order_item
FOR EACH ROW
EXECUTE FUNCTION fn_order_item_before_update();

-- No se borran fisicamente posiciones: se cancelan o reemplazan.
CREATE OR REPLACE FUNCTION fn_order_item_prevent_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'No se permite DELETE sobre order_item. Use estado CANCELADO o REEMPLAZADO';
END;
$$;

DROP TRIGGER IF EXISTS trg_order_item_prevent_delete ON order_item;
CREATE TRIGGER trg_order_item_prevent_delete
BEFORE DELETE ON order_item
FOR EACH ROW
EXECUTE FUNCTION fn_order_item_prevent_delete();

-- -------------------------------------------------------------
-- 12. Auditoria automatica de order_item
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_order_item_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_event_type VARCHAR(20);
    v_user_id    VARCHAR(80);
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO order_item_event (
            order_id,
            item_id,
            event_type,
            old_data,
            new_data,
            reason,
            created_by
        ) VALUES (
            NEW.order_id,
            NEW.item_id,
            'CREADO',
            NULL,
            to_jsonb(NEW),
            NULL,
            NEW.created_by
        );

        RETURN NEW;
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'CANCELADO' THEN
        v_event_type := 'CANCELADO';
    ELSIF NEW.status IS DISTINCT FROM OLD.status AND NEW.status = 'REEMPLAZADO' THEN
        v_event_type := 'REEMPLAZADO';
    ELSE
        v_event_type := 'MODIFICADO';
    END IF;

    v_user_id := COALESCE(NEW.changed_by, NEW.created_by);

    INSERT INTO order_item_event (
        order_id,
        item_id,
        event_type,
        old_data,
        new_data,
        reason,
        created_by
    ) VALUES (
        NEW.order_id,
        NEW.item_id,
        v_event_type,
        to_jsonb(OLD),
        to_jsonb(NEW),
        NEW.status_reason,
        v_user_id
    );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_order_item_audit_insert ON order_item;
CREATE TRIGGER trg_order_item_audit_insert
AFTER INSERT ON order_item
FOR EACH ROW
EXECUTE FUNCTION fn_order_item_audit();

DROP TRIGGER IF EXISTS trg_order_item_audit_update ON order_item;
CREATE TRIGGER trg_order_item_audit_update
AFTER UPDATE ON order_item
FOR EACH ROW
EXECUTE FUNCTION fn_order_item_audit();

-- -------------------------------------------------------------
-- 13. Total del pedido calculado desde posiciones activas
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_recalculate_order_total()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_id BIGINT;
BEGIN
    v_order_id := NEW.order_id;

    UPDATE restaurant_order ro
       SET total_price = COALESCE((
               SELECT SUM(oi.quantity * oi.unit_price)
                 FROM order_item oi
                WHERE oi.order_id = v_order_id
                  AND oi.status = 'ACTIVO'
           ), 0)
     WHERE ro.order_id = v_order_id;

    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_order_item_recalculate_total_insert ON order_item;
CREATE TRIGGER trg_order_item_recalculate_total_insert
AFTER INSERT ON order_item
FOR EACH ROW
EXECUTE FUNCTION fn_recalculate_order_total();

DROP TRIGGER IF EXISTS trg_order_item_recalculate_total_update ON order_item;
CREATE TRIGGER trg_order_item_recalculate_total_update
AFTER UPDATE OF quantity, status ON order_item
FOR EACH ROW
EXECUTE FUNCTION fn_recalculate_order_total();

-- -------------------------------------------------------------
-- 14. Validacion de tickets de cocina
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_kitchen_ticket_before_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_status VARCHAR(20);
BEGIN
    SELECT status
      INTO v_order_status
      FROM restaurant_order
     WHERE order_id = NEW.order_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pedido % no existe', NEW.order_id;
    END IF;

    IF v_order_status <> 'ABIERTO' THEN
        RAISE EXCEPTION 'Solo se pueden crear tickets de cocina para pedidos ABIERTO';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_kitchen_ticket_before_insert ON kitchen_ticket;
CREATE TRIGGER trg_kitchen_ticket_before_insert
BEFORE INSERT ON kitchen_ticket
FOR EACH ROW
EXECUTE FUNCTION fn_kitchen_ticket_before_insert();

CREATE OR REPLACE FUNCTION fn_kitchen_ticket_item_validate()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_ticket_order_id BIGINT;
    v_ticket_status   VARCHAR(20);
    v_item_order_id   BIGINT;
    v_item_status     VARCHAR(20);
    v_requires        BOOLEAN;
BEGIN
    SELECT order_id, status
      INTO v_ticket_order_id, v_ticket_status
      FROM kitchen_ticket
     WHERE ticket_id = NEW.ticket_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Ticket de cocina % no existe', NEW.ticket_id;
    END IF;

    IF v_ticket_status = 'IMPRESO' THEN
        RAISE EXCEPTION 'No se pueden agregar posiciones a un ticket ya impreso';
    END IF;

    SELECT order_id, status, requires_cooking_snapshot
      INTO v_item_order_id, v_item_status, v_requires
      FROM order_item
     WHERE item_id = NEW.order_item_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Posicion de pedido % no existe', NEW.order_item_id;
    END IF;

    IF v_item_order_id <> v_ticket_order_id THEN
        RAISE EXCEPTION 'El ticket y la posicion deben pertenecer al mismo pedido';
    END IF;

    IF v_item_status <> 'ACTIVO' THEN
        RAISE EXCEPTION 'Solo posiciones ACTIVO pueden enviarse a cocina';
    END IF;

    IF NOT v_requires THEN
        RAISE EXCEPTION 'La posicion % no requiere cocina y no puede incluirse en un ticket',
            NEW.order_item_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_kitchen_ticket_item_validate ON kitchen_ticket_item;
CREATE TRIGGER trg_kitchen_ticket_item_validate
BEFORE INSERT OR UPDATE ON kitchen_ticket_item
FOR EACH ROW
EXECUTE FUNCTION fn_kitchen_ticket_item_validate();

CREATE OR REPLACE FUNCTION fn_kitchen_ticket_item_protect_printed()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_ticket_status VARCHAR(20);
BEGIN
    SELECT status
      INTO v_ticket_status
      FROM kitchen_ticket
     WHERE ticket_id = OLD.ticket_id;

    IF v_ticket_status = 'IMPRESO' THEN
        RAISE EXCEPTION 'No se puede modificar ni eliminar el detalle de un ticket ya impreso';
    END IF;

    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_kitchen_ticket_item_protect_delete ON kitchen_ticket_item;
CREATE TRIGGER trg_kitchen_ticket_item_protect_delete
BEFORE DELETE ON kitchen_ticket_item
FOR EACH ROW
EXECUTE FUNCTION fn_kitchen_ticket_item_protect_printed();

-- -------------------------------------------------------------
-- 15. Registro de intentos de impresion
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_kitchen_ticket_print_before_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_status VARCHAR(20);
BEGIN
    -- Los intentos fallidos tambien se registran, pero para declarar una
    -- impresion exitosa el ticket debe seguir siendo valido.
    IF NEW.result = 'IMPRESO' THEN
        SELECT ro.status
          INTO v_order_status
          FROM kitchen_ticket kt
          JOIN restaurant_order ro ON ro.order_id = kt.order_id
         WHERE kt.ticket_id = NEW.ticket_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Ticket de cocina % no existe', NEW.ticket_id;
        END IF;

        IF v_order_status <> 'ABIERTO' THEN
            RAISE EXCEPTION 'No se puede imprimir el ticket %. El pedido no esta ABIERTO', NEW.ticket_id;
        END IF;

        IF NOT EXISTS (
            SELECT 1
              FROM kitchen_ticket_item
             WHERE ticket_id = NEW.ticket_id
        ) THEN
            RAISE EXCEPTION 'No se puede imprimir un ticket de cocina sin posiciones';
        END IF;

        IF EXISTS (
            SELECT 1
              FROM kitchen_ticket_item kti
              JOIN order_item oi ON oi.item_id = kti.order_item_id
             WHERE kti.ticket_id = NEW.ticket_id
               AND (oi.status <> 'ACTIVO' OR oi.requires_cooking_snapshot = FALSE)
        ) THEN
            RAISE EXCEPTION 'El ticket % contiene posiciones que ya no son validas para cocina', NEW.ticket_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_kitchen_ticket_print_before_insert ON kitchen_ticket_print;
CREATE TRIGGER trg_kitchen_ticket_print_before_insert
BEFORE INSERT ON kitchen_ticket_print
FOR EACH ROW
EXECUTE FUNCTION fn_kitchen_ticket_print_before_insert();

CREATE OR REPLACE FUNCTION fn_kitchen_ticket_print_after_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.result = 'IMPRESO' THEN
        UPDATE kitchen_ticket
           SET status = 'IMPRESO',
               printed_at = COALESCE(printed_at, NEW.attempted_at),
               printed_by = COALESCE(printed_by, NEW.attempted_by),
               print_attempts = print_attempts + 1,
               last_print_attempt_at = NEW.attempted_at,
               last_error = NULL
         WHERE ticket_id = NEW.ticket_id;
    ELSE
        UPDATE kitchen_ticket
           SET status = CASE WHEN status = 'IMPRESO' THEN 'IMPRESO' ELSE 'ERROR' END,
               print_attempts = print_attempts + 1,
               last_print_attempt_at = NEW.attempted_at,
               last_error = NEW.error_message
         WHERE ticket_id = NEW.ticket_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_kitchen_ticket_print_after_insert ON kitchen_ticket_print;
CREATE TRIGGER trg_kitchen_ticket_print_after_insert
AFTER INSERT ON kitchen_ticket_print
FOR EACH ROW
EXECUTE FUNCTION fn_kitchen_ticket_print_after_insert();

-- =============================================================
-- INDICES
-- =============================================================

CREATE INDEX IF NOT EXISTS idx_product_category
    ON product(category_id);

CREATE INDEX IF NOT EXISTS idx_product_active
    ON product(active);

CREATE INDEX IF NOT EXISTS idx_restaurant_order_business_date_status
    ON restaurant_order(business_date, status);

CREATE INDEX IF NOT EXISTS idx_restaurant_order_waiter_business_date
    ON restaurant_order(assigned_waiter_id, business_date);

CREATE INDEX IF NOT EXISTS idx_restaurant_order_created_at
    ON restaurant_order(created_at);

CREATE INDEX IF NOT EXISTS idx_order_item_order
    ON order_item(order_id);

CREATE INDEX IF NOT EXISTS idx_order_item_product
    ON order_item(product_id);

CREATE INDEX IF NOT EXISTS idx_order_item_category_snapshot
    ON order_item(category_id_snapshot);

CREATE INDEX IF NOT EXISTS idx_order_item_status
    ON order_item(status);

CREATE INDEX IF NOT EXISTS idx_order_item_event_item_created_at
    ON order_item_event(item_id, created_at);

CREATE INDEX IF NOT EXISTS idx_kitchen_ticket_order_status
    ON kitchen_ticket(order_id, status);

CREATE INDEX IF NOT EXISTS idx_kitchen_ticket_print_ticket_attempted_at
    ON kitchen_ticket_print(ticket_id, attempted_at);

-- =============================================================
-- VISTAS BASE PARA REPORTES
-- =============================================================

-- Vista detallada para dashboards y reportes historicos.
-- Utiliza snapshots de order_item, no los datos actuales del maestro.
CREATE OR REPLACE VIEW vw_order_item_reporting AS
SELECT
    ro.order_id,
    ro.business_date,
    ro.status AS order_status,
    ro.table_id,
    rt.name AS table_name,
    ro.assigned_waiter_id,
    au.full_name AS waiter_name,
    oi.item_id,
    oi.product_id,
    oi.product_name_snapshot AS product_name,
    oi.category_id_snapshot AS category_id,
    oi.category_name_snapshot AS category_name,
    oi.requires_cooking_snapshot AS requires_cooking,
    oi.quantity,
    oi.unit_price,
    oi.unit_cost,
    oi.quantity * oi.unit_price AS line_amount,
    oi.quantity * oi.unit_cost AS line_cost,
    oi.quantity * (oi.unit_price - oi.unit_cost) AS estimated_margin,
    oi.status AS item_status,
    oi.created_at AS item_created_at
FROM restaurant_order ro
JOIN restaurant_table rt
  ON rt.table_id = ro.table_id
JOIN app_user au
  ON au.user_id = ro.assigned_waiter_id
JOIN order_item oi
  ON oi.order_id = ro.order_id;

-- Demanda diaria efectiva: excluye borradores, pedidos cancelados y
-- posiciones canceladas/reemplazadas.
CREATE OR REPLACE VIEW vw_daily_product_demand AS
SELECT
    business_date,
    product_id,
    product_name,
    category_id,
    category_name,
    SUM(quantity) AS total_quantity,
    SUM(line_amount) AS total_ordered_amount,
    SUM(line_cost) AS total_estimated_cost,
    SUM(estimated_margin) AS total_estimated_margin
FROM vw_order_item_reporting
WHERE order_status IN ('ABIERTO', 'CERRADO')
  AND item_status = 'ACTIVO'
GROUP BY
    business_date,
    product_id,
    product_name,
    category_id,
    category_name;

COMMIT;
