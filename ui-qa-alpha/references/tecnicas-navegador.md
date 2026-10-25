# Técnicas del navegador para QA alfa

Aprendidas en rondas reales. Cada una evita un error que ya pasó. Las direcciones y nombres concretos salen de las variables de adopción de `SKILL.md` §0.

## Índice
1. Navegador y host
2. Recargas en caliente
3. Login
4. Controles de Radix (select, combobox, menús)
5. Diálogos: cerrar sin disparar acciones
6. Toasts efímeros
7. Registrar peticiones
8. PDFs sin descargar
9. Pasarela de pago de pruebas (Stripe Checkout)
10. Tareas en segundo plano
11. Coordenadas y capturas
12. Lectura de estado sin escribir

## 1. Navegador y host
- Usa el navegador que indique el usuario; si no dice nada, el integrado de la herramienta.
- Siempre `{{stand_url}}` (local). `{{stand_url_public}}` solo para lo que depende del host real, sin iniciar sesión (`SKILL.md` §2). Comprueba la instancia con `{{version_endpoint}}`.
- Para leer, prefiere el texto de la página, el árbol de accesibilidad o JavaScript; la captura, solo para estética y coordenadas.

## 2. Recargas en caliente
Un stand de desarrollo recarga en caliente cuando Code edita. Síntomas: página en negro con errores de contexto en consola, texto vacío, errores 500 o «servicio no disponible» puntuales. No es un fallo de la app si una recarga lo arregla: recarga y repite. Pero si una operación falló durante un reinicio, **comprueba si se aplicó igualmente** (ya pasó: el aviso decía error y la cancelación sí se había aplicado); eso sí es un hallazgo.

## 3. Login
- Localiza los campos por su texto de ejemplo o su etiqueta y rellénalos con la herramienta de formularios; luego el botón de enviar.
- Cierra sesión entre roles y comprueba quién eres (nombre visible) antes de actuar.
- El primer render tras el login puede llegar sin el perfil cargado: si un formulario aparece vacío, recarga antes de concluir, y anótalo como DUDA de carrera si el usuario podría sobrescribir sus datos.

## 4. Controles de Radix
- Un click sintético en el trigger no abre un `Select`. Usa `trigger.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,pointerType:'mouse',button:0}))`, espera unos 700 ms y haz `.click()` en el `[role=option]`.
- Los combobox con buscador se abren mejor con un click real por coordenadas, escribiendo después con el teclado.
- El valor real está en el `<select>` oculto que acompaña al trigger; compáralo con el texto del trigger. Un trigger vacío (atributo `data-placeholder`) con el formulario aparentemente rellenado es un fallo visible.
- Menús de acciones: botón con nombre accesible tipo «Acciones»; las opciones son `[role=menuitem]`.

## 5. Diálogos: cerrar sin disparar acciones
**Nunca cierres un diálogo pulsando «el primer botón»**: en algunos diálogos el primero descarga un fichero a las carpetas del usuario. Cierra con Escape o buscando el botón por su texto («Cerrar», «Cancelar»). En confirmaciones, elige el botón por su texto exacto.

## 6. Toasts efímeros
Los toasts (sonner) duran unos 4 s. Para no perderlos, instala un observador ANTES de la acción:
```js
window.__toasts=[]; new MutationObserver(()=>{document.querySelectorAll('[data-sonner-toast]').forEach(t=>{const x=t.innerText; if(x&&!window.__toasts.includes(x)) window.__toasts.push(x);});}).observe(document.body,{childList:true,subtree:true});
```
Si el toast sale al cargar una página, navega y sondea de inmediato durante unos 8 s recogiendo `[data-sonner-toast]`. Cuenta los toasts: dos avisos para un mismo hecho (uno con un código en crudo) es un hallazgo.

## 7. Registrar peticiones
**Solo si te lo piden expresamente para una tarea concreta** (el veredicto sale de la UI; ver SKILL.md §2).
Envuelve `fetch` para capturar estado y cuerpo de lo que interese:
```js
window.__log=[]; const of=window.fetch; window.fetch=async(...a)=>{const r=await of(...a); try{const u=typeof a[0]==='string'?a[0]:a[0].url; if(/checkout|cart/.test(u)) r.clone().text().then(t=>window.__log.push({u,s:r.status,b:t}));}catch(e){} return r;};
```
Ajusta la expresión a las rutas que pruebes. Se pierde al navegar: reinstálalo en cada página. En un PUT o POST registra también el cuerpo enviado (`a[1].body`): así se ve si se iba a guardar algo indebido sin llegar a guardarlo.

## 8. PDFs sin descargar
Intercepta la creación del blob y bloquea la descarga:
```js
window.__blobs=[]; const oc=URL.createObjectURL; URL.createObjectURL=b=>{if(b instanceof Blob) window.__blobs.push(b); return oc.call(URL,b);};
HTMLAnchorElement.prototype.click=function(){window.__blocked=(window.__blocked||0)+1;}; window.open=()=>null;
```
Con `HTMLAnchorElement.prototype.click` anulado, los enlaces tampoco navegan por `.click()`: navega con la herramienta.
Para leerlo en la página: localiza `<<…>> stream`, toma `/Length N`, descomprime con `DecompressionStream('deflate')`, construye el mapa de glifos con los CMaps ToUnicode (`beginbfchar` / `beginbfrange`) y traduce los operandos hex de `Tj`/`TJ`. Después comprueba que no cayó nada en disco (`find ~/Documents ~/Downloads -newermt '<inicio>' -type f`).

## 9. Pasarela de pago de pruebas (Stripe Checkout)
- Número de tarjeta: localiza el campo por su texto de ejemplo («1234 1234 1234 1234»); luego tabula a caducidad, CVC y titular escribiendo con el teclado.
- Usa `{{payment_test_data}}`. En Stripe, la tarjeta de pruebas habitual es 4242 4242 4242 4242 con una caducidad **lejana** (p. ej. 12/49): una cercana puede rechazarla el reloj real de la pasarela.
- Desmarca «guardar mis datos» si aparece.
- Revisa la página de la pasarela como parte de la UX (idioma, concepto del pedido).

## 10. Tareas en segundo plano
En `{{background_tasks_ui}}`, localiza el botón de ejecutar ahora de la tarjeta cuyo texto contiene el identificador de la tarea. Pide a Code el orden útil para cada flujo (p. ej. tras cancelar un pedido: reconciliación → reintento de devolución → emisión de documentos). El detalle de una ejecución suele estar en su historial; ciérralo por texto (§5). Si una operación con la pasarela espera un plazo antes de reintentarse, no relances la tarea en bucle: pregúntale el plazo a Code.

## 11. Coordenadas y capturas
Las capturas pueden ir escaladas respecto al viewport: calcula con `getBoundingClientRect()` por la razón de escala. Tras navegar o hacer scroll, toma una captura nueva antes de un click por coordenadas.

## 12. Lectura de estado sin escribir
- Las API públicas de lectura solo se consultan si te lo piden expresamente para una tarea concreta; por defecto, la evidencia es la pantalla.
- Logs y base de datos, solo con `{{read_commands}}` y solo lectura.
