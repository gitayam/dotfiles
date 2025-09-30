# Development Partnership for Muse & Co
*Modern Cloudflare Pages + React Development Guide*

We're building production-quality code for Muse & Co on Cloudflare's edge platform. Your role is to create maintainable, efficient solutions while catching potential issues early.

When you seem stuck or overly complex, I'll redirect you - my guidance helps you stay on track.

## 🚨 CRITICAL: Code Quality is MANDATORY
**ALL linting and build issues are BLOCKING - EVERYTHING must be ✅ GREEN!**
No errors. No formatting issues. No linting problems. Zero tolerance.
These are not suggestions. Fix ALL issues before continuing.

## CRITICAL WORKFLOW - ALWAYS FOLLOW THIS!

### Research → Plan → Implement
**NEVER JUMP STRAIGHT TO CODING!** Always follow this sequence:
1. **Research**: Explore the codebase, understand existing patterns
2. **Plan**: Create a detailed implementation plan and verify it with me
3. **Implement**: Execute the plan with validation checkpoints

When asked to implement any feature, you'll first say: "Let me research the codebase and create a plan before implementing."

For complex architectural decisions or challenging problems, use **"ultrathink"** to engage maximum reasoning capacity. Say: "Let me ultrathink about this architecture before proposing a solution."

### USE MULTIPLE AGENTS!
*Leverage subagents aggressively* for better results:

* Spawn agents to explore different parts of the codebase in parallel
* Use one agent to write tests while another implements features
* Delegate research tasks: "I'll have an agent investigate the database schema while I analyze the API structure"
* For complex refactors: One agent identifies changes, another implements them

Say: "I'll spawn agents to tackle different aspects of this problem" whenever a task has multiple independent parts.

### Reality Checkpoints
**Stop and validate** at these moments:
- After implementing a complete feature
- Before starting a new major component
- When something feels wrong
- Before declaring "done"
- **WHEN LINTERS OR BUILD FAILS** ❌

**Build & Lint Commands**:
```bash
# Build (catch errors early)
npm run build

# Lint TypeScript
npm run lint

# Preview production build locally
npm run preview
```

> Why: You can lose track of what's actually working. These checkpoints prevent cascading failures.

### 🚨 CRITICAL: Build/Lint Failures Are BLOCKING
**When build or lint reports ANY issues, you MUST:**
1. **STOP IMMEDIATELY** - Do not continue with other tasks
2. **FIX ALL ISSUES** - Address every ❌ issue until everything is ✅ GREEN
3. **VERIFY THE FIX** - Re-run the failed command to confirm it's fixed
4. **CONTINUE ORIGINAL TASK** - Return to what you were doing before the interrupt
5. **NEVER IGNORE** - There are NO warnings, only requirements

This includes:
- TypeScript type errors
- ESLint violations
- Build failures
- Missing imports
- Runtime errors in production
- ALL other checks

Your code must be 100% clean. No exceptions.

**Recovery Protocol:**
- When interrupted by a failure, maintain awareness of your original task
- After fixing all issues and verifying the fix, continue where you left off
- Use the todo list to track both the fix and your original task

## 🔧 Cloudflare Development Environment

### Project Structure
```
muse-customer/
├── functions/              # Cloudflare Pages Functions (API routes)
│   └── api/               # /api/* endpoints
│       ├── surveys.ts     # → /api/surveys
│       ├── send-email.ts  # → /api/send-email
│       └── mx-test.ts     # → /api/mx-test
├── src/
│   ├── components/        # React components
│   │   ├── ui/           # Reusable UI components
│   │   ├── global/       # Layout (header, footer)
│   │   ├── cart/         # Shopping cart
│   │   ├── chatbot/      # Chatbot widget
│   │   └── lazy/         # Lazy-loaded components
│   ├── pages/            # Page components
│   ├── contexts/         # React Context providers
│   ├── hooks/            # Custom React hooks
│   ├── lib/              # Utilities
│   └── stores/           # Zustand stores
├── public/               # Static assets
├── dist/                 # Build output (deploy this)
├── wrangler.toml         # Cloudflare configuration
├── vite.config.ts        # Vite build config
├── tailwind.config.js    # Tailwind CSS config
├── .env                  # Local environment variables
└── package.json          # Dependencies & scripts
```

### Development Setup
```bash
# 1. Install dependencies
npm install

# 2. Set up environment variables
cp .env.example .env
# Edit .env with your values

# 3. Set up D1 database (first time only)
npm run db:setup

# 4. Start development server
npm run dev
# → Opens http://localhost:5173

# 5. (Optional) Test with Wrangler for API functions
npx wrangler pages dev dist --compatibility-date=2025-09-21
# → Runs on http://localhost:8788
```

### Configuration Files

#### wrangler.toml
Cloudflare Pages configuration:
```toml
name = "muse-customer"
compatibility_date = "2024-09-21"

# D1 Database bindings
[[d1_databases]]
binding = "DB"
database_name = "muse-and-co-db"
database_id = "your-database-id"

# Build configuration
[build]
command = "npm run build"

pages_build_output_dir = "dist"
```

#### .env (Local Development)
```env
# Vite environment variables (must start with VITE_)
VITE_API_URL=http://localhost:8788
VITE_CHATBOT_API=https://api.example.com

# Wrangler will use these for local development
```

### Secrets Management
```bash
# Set secret for production (Pages Function access)
npx wrangler pages secret put SECRET_NAME --project-name muse-customer

# List all secrets
npx wrangler pages secret list --project-name muse-customer

# Remove secret
npx wrangler pages secret remove SECRET_NAME --project-name muse-customer
```

**Access secrets in Pages Functions**:
```typescript
export async function onRequest(context: any) {
  const { env } = context
  const apiKey = env.SECRET_NAME  // From Cloudflare dashboard or wrangler
  // ...
}
```

## Cloudflare Pages Functions (API Routes)

### File-Based Routing
```
/functions/api/surveys.ts     → /api/surveys
/functions/api/send-email.ts  → /api/send-email
/functions/api/mx-test.ts     → /api/mx-test
```

### Function Pattern
```typescript
// functions/api/example.ts
export async function onRequest(context: any) {
  const { request, env } = context

  // CORS headers (for browser access)
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  }

  // Handle OPTIONS (preflight)
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders })
  }

  try {
    // Parse JSON body (for POST/PUT)
    const body = request.method !== 'GET' ? await request.json() : null

    // Access D1 database
    const result = await env.DB.prepare(
      'SELECT * FROM users WHERE email = ?'
    ).bind(body.email).first()

    // Access secrets
    const apiKey = env.API_KEY

    // Return JSON response
    return new Response(JSON.stringify({
      success: true,
      data: result
    }), {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        ...corsHeaders
      }
    })
  } catch (error: any) {
    return new Response(JSON.stringify({
      success: false,
      error: error.message
    }), {
      status: 500,
      headers: {
        'Content-Type': 'application/json',
        ...corsHeaders
      }
    })
  }
}
```

## Cloudflare D1 Database

### Database Access in Pages Functions
```typescript
// Query with parameters (prevents SQL injection)
const user = await env.DB.prepare(
  'SELECT * FROM users WHERE email = ?'
).bind(email).first()

// Get all results
const users = await env.DB.prepare(
  'SELECT * FROM users WHERE active = ?'
).bind(true).all()

// Execute mutation
const result = await env.DB.prepare(
  'INSERT INTO users (email, name) VALUES (?, ?)'
).bind(email, name).run()

// Batch operations
const results = await env.DB.batch([
  env.DB.prepare('UPDATE users SET ...'),
  env.DB.prepare('INSERT INTO logs ...')
])
```

### D1 CLI Commands
```bash
# Create database
npx wrangler d1 create muse-and-co-db

# List databases
npx wrangler d1 list

# Execute SQL
npx wrangler d1 execute muse-and-co-db --file=./schema.sql

# Execute command directly
npx wrangler d1 execute muse-and-co-db --command="SELECT * FROM users LIMIT 5"
```

## React + Vite + TypeScript Patterns

### FORBIDDEN - NEVER DO THESE:
- **NO `any` type** - Use proper types or `unknown`
- **NO console.log in production** - Use proper logging or remove before deploy
- **NO Framer Motion** - Causes production issues; use CSS animations instead
- **NO missing imports** - Always import all used components/icons
- **NO React Portal** - Problematic with Vite; use inline modals
- **NO inline event handlers** - Create named functions for clarity
- **NO direct DOM manipulation** - Use React state
- **NO magic strings/numbers** - Use constants
- **NO TODOs in final code**

### Required Standards:
- **Explicit return types** on all functions
- **Proper error boundaries** for error handling
- **Custom hooks** for reusable logic
- **Zustand stores** for complex global state
- **React Context** for simple shared state
- **Proper loading and error states** in all components
- **Accessibility**: Proper ARIA labels and keyboard navigation
- **Mobile-first responsive design** with Tailwind
- **Lazy loading** for route-based code splitting

### Component Structure
```typescript
// src/components/Example.tsx
import { useState } from 'react'
import { Button } from './ui/button'
import { AlertCircle } from 'lucide-react'

interface ExampleProps {
  title: string
  onSubmit: (data: FormData) => Promise<void>
}

export default function Example({ title, onSubmit }: ExampleProps) {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleSubmit = async () => {
    setLoading(true)
    setError(null)

    try {
      await onSubmit({ /* data */ })
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="p-4">
      <h2 className="text-xl font-bold">{title}</h2>

      {error && (
        <div className="text-red-600 flex items-center gap-2">
          <AlertCircle className="h-4 w-4" />
          {error}
        </div>
      )}

      <Button
        onClick={handleSubmit}
        disabled={loading}
      >
        {loading ? 'Loading...' : 'Submit'}
      </Button>
    </div>
  )
}
```

### Zustand Store Pattern
```typescript
// src/stores/cartStore.ts
import { create } from 'zustand'
import { persist } from 'zustand/middleware'

interface CartItem {
  id: string
  name: string
  price: number
  quantity: number
}

interface CartStore {
  items: CartItem[]
  addItem: (item: CartItem) => void
  removeItem: (id: string) => void
  clearCart: () => void
  total: () => number
}

export const useCartStore = create<CartStore>()(
  persist(
    (set, get) => ({
      items: [],

      addItem: (item) => set((state) => ({
        items: [...state.items, item]
      })),

      removeItem: (id) => set((state) => ({
        items: state.items.filter(item => item.id !== id)
      })),

      clearCart: () => set({ items: [] }),

      total: () => get().items.reduce(
        (sum, item) => sum + (item.price * item.quantity),
        0
      )
    }),
    {
      name: 'cart-storage'
    }
  )
)
```

### Lazy Loading Pattern
```typescript
// src/components/lazy/LazyComponents.tsx
import { lazy } from 'react'

export const LazyHomePage = lazy(() => import('../../pages/HomePage'))
export const LazyMenuPage = lazy(() => import('../../pages/MenuPage'))
export const LazyCheckout = lazy(() => import('../../pages/CheckoutPage'))

// In App.tsx
import { Suspense } from 'react'
import { LazyHomePage } from './components/lazy/LazyComponents'

function App() {
  return (
    <Suspense fallback={<LoadingSpinner />}>
      <Routes>
        <Route path="/" element={<LazyHomePage />} />
      </Routes>
    </Suspense>
  )
}
```

## Modal & UI Best Practices

### Critical Lessons from Production Issues

#### ❌ AVOID: React Portal + Card Components
```typescript
// DON'T DO THIS - Causes rendering issues
import { Portal } from './ui/portal'
import { Card } from './ui/card'

<Portal>
  <Card className="fixed z-50">
    {/* Content */}
  </Card>
</Portal>
```

#### ✅ DO THIS: Inline Styles + Simple Divs
```typescript
// CORRECT - Works reliably in Cloudflare Pages
export default function Modal({ isOpen, onClose, children }: ModalProps) {
  if (!isOpen) return null

  return (
    <>
      {/* Overlay */}
      <div
        onClick={onClose}
        style={{
          position: 'fixed',
          top: 0,
          left: 0,
          width: '100vw',
          height: '100vh',
          backgroundColor: 'rgba(0, 0, 0, 0.5)',
          zIndex: 9999
        }}
      />

      {/* Modal */}
      <div style={{
        position: 'fixed',
        top: '50%',
        left: '50%',
        transform: 'translate(-50%, -50%)',
        zIndex: 10000,
        backgroundColor: 'white',
        borderRadius: '8px',
        padding: '24px',
        maxWidth: '500px',
        maxHeight: '80vh',
        overflow: 'auto'
      }}>
        {children}
      </div>
    </>
  )
}
```

### Z-Index Management
- **Header/Nav**: `z-50`
- **Dropdowns**: `z-40`
- **Modal Overlay**: `z-[9999]`
- **Modal Content**: `z-[10000]`
- **Toasts**: `z-[10001]`

**Use inline styles for z-index** - Tailwind/CSS classes can be overridden.

### CSS Animations Over Framer Motion
```typescript
// ❌ AVOID: Framer Motion (bundle bloat + production issues)
import { motion } from 'framer-motion'
<motion.div animate={{ scale: 1.1 }} />

// ✅ USE: Tailwind CSS animations
<div className="hover:scale-110 active:scale-95 transition-transform duration-200">
  {/* Content */}
</div>
```

## Deployment Workflow

### Local Testing (ALWAYS DO BEFORE DEPLOYING)
```bash
# 1. Build production bundle
npm run build

# 2. Preview locally
npm run preview
# → http://localhost:4173

# 3. Test with Wrangler (for API functions)
npx wrangler pages dev dist --compatibility-date=2025-09-21
# → http://localhost:8788

# 4. Check for errors in browser console
# 5. Test all interactive elements
```

### Deploy to Cloudflare Pages
```bash
# Option 1: Using wrangler
npx wrangler pages deploy dist --project-name muse-customer

# Option 2: Using npm script
npm run deploy

# Check deployment status
npx wrangler pages deployment list --project-name muse-customer
```

### GitHub Actions CI/CD (Recommended)
```yaml
# .github/workflows/deploy.yml
name: Deploy to Cloudflare Pages

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Setup Node
        uses: actions/setup-node@v3
        with:
          node-version: '18'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Lint
        run: npm run lint

      - name: Build
        run: npm run build

      - name: Deploy to Cloudflare Pages
        uses: cloudflare/wrangler-action@v3
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          command: pages deploy dist --project-name=muse-customer
```

### GitHub CLI Usage
```bash
# Create PR
gh pr create --title "Feature: Add payment integration" --body "Implements MX Merchant API"

# List PRs
gh pr list

# View PR
gh pr view 123

# Merge PR
gh pr merge 123

# Create issue
gh issue create --title "Bug: Modal not appearing" --body "Steps to reproduce..."

# List issues
gh issue list
```

## Testing & Debugging

### Testing Checklist
- [ ] Build passes: `npm run build`
- [ ] Lint passes: `npm run lint`
- [ ] Preview works: `npm run preview`
- [ ] All modals render correctly
- [ ] All buttons have onClick handlers
- [ ] No console errors in browser
- [ ] Mobile responsive design works
- [ ] All imports are present
- [ ] No TypeScript errors
- [ ] API endpoints work
- [ ] Database queries execute

### Debugging Production Issues
When encountering issues in production:

1. **Check browser console** for errors
2. **Inspect network tab** for failed API requests
3. **Test in incognito** (rule out caching)
4. **Build and preview locally**: `npm run build && npm run preview`
5. **Inspect built bundle** in `dist/assets/`
6. **Search for undefined** variables/components
7. **Check for missing imports**
8. **Verify all dependencies** are installed
9. **Check Cloudflare Pages logs** in dashboard

### Common Gotchas

#### 1. Development vs Production Behavior
- Development uses source files directly (hot reload)
- Production uses minified bundles (optimized)
- Some issues only appear in production builds
- **Always test with `npm run preview` before deploying**

#### 2. Missing Imports
```typescript
// ❌ This compiles but crashes at runtime
<Sparkles />  // Never imported

// ✅ Always import explicitly
import { Sparkles } from 'lucide-react'
<Sparkles />
```

#### 3. Framer Motion in Production
- Works in dev, breaks in production
- Error: "Can't find variable: motion"
- **Solution**: Remove framer-motion, use CSS animations

#### 4. Modal Z-Index Issues
- Tailwind classes can be overridden
- **Solution**: Use inline styles for critical z-index

#### 5. Browser Caching
- Cloudflare caches aggressively
- Test in incognito or different browser
- Each deployment gets unique URL

## Implementation Standards

### Our code is complete when:
- ✅ Build succeeds with zero errors
- ✅ Linter passes with zero issues
- ✅ Feature works end-to-end locally
- ✅ Tested in production preview mode
- ✅ No console errors in browser
- ✅ Mobile responsive
- ✅ Accessible (keyboard nav, ARIA labels)
- ✅ Proper loading/error states
- ✅ Code follows project patterns
- ✅ Old/dead code removed

### Frontend Testing Strategy
- Components → Test user interactions and edge cases
- Custom hooks → Test in isolation
- API calls → Test locally with Wrangler
- Forms → Test validation and submission
- State management → Test store actions
- Modals → Test opening, closing, interactions
- Responsive → Test on mobile and desktop

## Performance & Security

### Frontend Performance:
- Use React.memo for expensive components
- Implement lazy loading for routes
- Optimize bundle size with code splitting
- Use Tailwind's purge for smaller CSS
- Compress images and use modern formats
- Leverage Cloudflare CDN caching

### Security Always:
- Validate all inputs (frontend + backend)
- Use parameterized queries for D1 (prevents SQL injection)
- Store secrets in Cloudflare (never in code)
- Implement rate limiting on API endpoints
- Use HTTPS (Cloudflare provides this)
- Implement CORS properly
- Never expose sensitive data in frontend

## Communication Protocol

### Progress Updates:
```
✓ Implemented user survey API (tested with curl)
✓ Added frontend survey form
✗ Found issue with email validation - investigating
```

### Suggesting Improvements:
"The current approach works, but I notice [observation].
Would you like me to [specific improvement]?"

### When Stuck:
"I see two approaches:
1. [Option A with pros/cons]
2. [Option B with pros/cons]
Which would you prefer?"

## Problem-Solving Together

When you're stuck or confused:
1. **Stop** - Don't spiral into complex solutions
2. **Research** - Check existing patterns in the codebase
3. **Delegate** - Consider spawning agents for parallel investigation
4. **Ultrathink** - For complex problems, engage deeper reasoning
5. **Step back** - Re-read the requirements
6. **Simplify** - The simple solution is usually correct
7. **Ask** - Get clarification before proceeding

## Common Development Tasks

### Adding a New API Endpoint
```bash
# 1. Create function file
touch functions/api/new-endpoint.ts

# 2. Implement function (see pattern above)
# 3. Test locally
curl http://localhost:8788/api/new-endpoint

# 4. Test in production preview
npm run build && npm run preview
curl http://localhost:4173/api/new-endpoint

# 5. Deploy
npm run deploy
```

### Adding a New Page
```bash
# 1. Create page component
touch src/pages/NewPage.tsx

# 2. Create lazy wrapper
# Add to src/components/lazy/LazyComponents.tsx

# 3. Add route
# Update src/App.tsx

# 4. Test
npm run dev
```

### Adding D1 Database Query
```typescript
// In functions/api/example.ts
export async function onRequest(context: any) {
  const { env } = context

  // Simple query
  const user = await env.DB.prepare(
    'SELECT * FROM users WHERE id = ?'
  ).bind(userId).first()

  // Multiple results
  const users = await env.DB.prepare(
    'SELECT * FROM users WHERE active = 1'
  ).all()

  // Insert/Update
  const result = await env.DB.prepare(
    'INSERT INTO logs (message) VALUES (?)'
  ).bind(message).run()

  return new Response(JSON.stringify({ user }), {
    headers: { 'Content-Type': 'application/json' }
  })
}
```

## Working Together

- This is always a feature branch - no backwards compatibility needed
- When in doubt, we choose clarity over cleverness
- Delete old code when replacing - no commented-out code
- **REMINDER**: If this file hasn't been referenced in 30+ minutes, RE-READ IT!
- Simple, obvious solutions are usually better
- My guidance helps you stay focused on what matters

---

**Last Updated**: September 27, 2025
**Version**: 2.0 (Cloudflare-focused)
**Stack**: React 18 + Vite + TypeScript + Cloudflare Pages + D1