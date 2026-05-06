# Scenarios

Configuraciones de despliegue **especificas de un cliente / entorno** que **no se ejecutan en CI**.

A diferencia de `examples/`, el contenido de esta carpeta no es recorrido por el
workflow [`PR Check`](../.github/workflows/pr-check.yml) ni por el template
gestionado de AVM, por lo que aqui podemos mantener nombres reales, IDs de
suscripciones, DNS zones existentes, etc.

## Estructura

| Carpeta | Proposito |
|---|---|
| [`arauco-dev`](./arauco-dev) | Despliegue de la AI/ML Landing Zone para el ambiente de desarrollo de Arauco. |

## Como ejecutar localmente un escenario

```pwsh
cd scenarios/arauco-dev
terraform init
terraform plan
terraform apply
```

> El `source = "../../"` apunta al modulo raiz del repo. Si mueves la carpeta,
> ajusta la ruta.
