```prompt
---
description: Create FastAPI endpoints for AccuBrief with proper authentication and multi-tenancy
tools:
  - create_file
  - read_file
  - replace_string_in_file
  - semantic_search
  - list_code_usages
---

# Create FastAPI Endpoint

You are a FastAPI expert specializing in REST APIs, Pydantic validation, and multi-tenant architectures. Create API endpoints for AccuBrief following project patterns.

## Critical Context

AccuBrief uses:
- **FastAPI** with async support
- **SQLAlchemy 2.0+** with PostgreSQL
- **Pydantic 2.0+** for validation
- **Multi-tenancy** via tenant_id filtering
- **Functional services** (factory pattern, not classes)
- **Soft delete** (never hard delete)

## API Route Template

```python
# api/v1/resource.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.core.security import get_current_tenant
from app.schemas.resource import (
    CreateResourceRequest,
    CreateResourceResponse,
    ResourceResponse
)
from app.services.resource_service import create_resource_service
from app.models.db import get_db

router = APIRouter(prefix="/v1/resources", tags=["resources"])


@router.post("/", response_model=CreateResourceResponse)
async def create_resource(
    request: CreateResourceRequest,
    tenant = Depends(get_current_tenant),
    db: Session = Depends(get_db)
):
    """
    Create a new resource.
    
    - **tenant**: Automatically resolved from API key
    - **request**: Resource creation data
    """
    # 1. Get service
    service = create_resource_service(db)
    
    # 2. Execute with tenant isolation
    resource = service["create_resource"](request, tenant.id)
    
    # 3. Return response
    return CreateResourceResponse(
        resource_id=resource.id,
        created_at=resource.created_at
    )


@router.get("/{resource_id}", response_model=ResourceResponse)
async def get_resource(
    resource_id: str,
    tenant = Depends(get_current_tenant),
    db: Session = Depends(get_db)
):
    """
    Get a resource by ID.
    
    - **resource_id**: The unique resource identifier
    - **tenant**: Automatically resolved from API key
    """
    service = create_resource_service(db)
    resource = service["get_resource"](resource_id, tenant.id)
    
    if not resource:
        raise HTTPException(status_code=404, detail="Resource not found")
    
    return ResourceResponse.from_orm(resource)


@router.delete("/{resource_id}", status_code=204)
async def delete_resource(
    resource_id: str,
    tenant = Depends(get_current_tenant),
    db: Session = Depends(get_db)
):
    """
    Soft delete a resource.
    
    - **resource_id**: The unique resource identifier
    - **tenant**: Automatically resolved from API key
    """
    service = create_resource_service(db)
    
    # Soft delete - never hard delete
    success = service["delete_resource"](resource_id, tenant.id)
    
    if not success:
        raise HTTPException(status_code=404, detail="Resource not found")
    
    return None
```

## Service Template

```python
# services/resource_service.py
from sqlalchemy.orm import Session
from datetime import datetime
from app.models.resource_model import ResourceModel
from app.schemas.resource import CreateResourceRequest
from app.utils.id_utils import generate_resource_id


def create_resource_service(db: Session):
    """Factory function returning resource operations."""
    
    def create_resource(request: CreateResourceRequest, tenant_id: str) -> ResourceModel:
        resource = ResourceModel(
            id=generate_resource_id(),
            tenant_id=tenant_id,
            status="active",
            name=request.name,
            created_at=datetime.utcnow()
        )
        db.add(resource)
        db.commit()
        db.refresh(resource)
        return resource
    
    def get_resource(resource_id: str, tenant_id: str) -> ResourceModel | None:
        return db.query(ResourceModel).filter(
            ResourceModel.id == resource_id,
            ResourceModel.tenant_id == tenant_id,
            ResourceModel.status != "DELETED"
        ).first()
    
    def delete_resource(resource_id: str, tenant_id: str) -> bool:
        resource = get_resource(resource_id, tenant_id)
        if not resource:
            return False
        
        # Soft delete - never hard delete
        resource.status = "DELETED"
        resource.deleted_at = datetime.utcnow()
        db.commit()
        return True
    
    return {
        "create_resource": create_resource,
        "get_resource": get_resource,
        "delete_resource": delete_resource,
    }
```

## Schema Template

```python
# schemas/resource.py
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class CreateResourceRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None
    
    class Config:
        json_schema_extra = {
            "example": {
                "name": "My Resource",
                "description": "Optional description"
            }
        }


class CreateResourceResponse(BaseModel):
    resource_id: str
    created_at: datetime


class ResourceResponse(BaseModel):
    id: str
    name: str
    description: Optional[str]
    status: str
    created_at: datetime
    
    class Config:
        from_attributes = True
```

## Model Template

```python
# models/resource_model.py
from sqlalchemy import Column, String, DateTime, Text
from datetime import datetime
from app.models.db import Base


class ResourceModel(Base):
    __tablename__ = "resources"
    
    id = Column(String, primary_key=True)  # res_xxx
    tenant_id = Column(String, nullable=False, index=True)
    
    # Business fields
    name = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    status = Column(String(50), default="active")
    
    # Timestamps
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    deleted_at = Column(DateTime, nullable=True)
    
    # Audit fields
    created_by = Column(String, nullable=True)
    updated_by = Column(String, nullable=True)
    deleted_by = Column(String, nullable=True)
```

## Critical Checklist

Before submitting, verify:

- [ ] All routes use `Depends(get_current_tenant)` for authentication
- [ ] All queries filter by `tenant_id`
- [ ] No hard deletes (use soft delete pattern)
- [ ] Pydantic schemas for request/response validation
- [ ] Proper HTTP status codes (201 create, 204 delete, 404 not found)
- [ ] Type hints on all functions
- [ ] Docstrings with parameter descriptions
- [ ] Factory function pattern for services (not classes)
```
